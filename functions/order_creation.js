/**
 * YummBU — Server-Authoritative Order Creation Engine (Phase 4.1)
 * 
 * Security Invariants:
 * 1. Customer UID derived strictly from authenticated authContext.
 * 2. Client customerId spoofing is strictly rejected (permission-denied).
 * 3. Shop existence and active status verified against authoritative catalog.
 * 4. Menu items verified against shop catalog (existence, availability, shop assignment).
 * 5. Item prices, option adjustments, and item subtotals derived strictly from catalog data.
 * 6. Delivery charges derived strictly from authoritative shop document.
 * 7. Subtotal, grandTotal, and totalAmount computed authoritatively on server.
 * 8. Initial status strictly set to 'placed'.
 * 9. Server timestamps and acceptDeadline (+20 min) derived on server.
 * 10. Atomic persistence of final order document in orders/{orderId}.
 * 11. Cost/read efficiency: duplicate menu items in request reuse loaded catalog doc.
 */

const crypto = require("crypto");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

/**
 * Builds a deterministic cartKey for a menuItem + options combination.
 * Matches Flutter client `CartItem.buildCartKey` sorting logic.
 * 
 * @param {string} menuItemId
 * @param {Array} options
 * @returns {string} deterministic key
 */
function buildDeterministicCartKey(menuItemId, options) {
  if (!options || !Array.isArray(options) || options.length === 0) {
    return menuItemId;
  }
  const sorted = [...options].sort((a, b) => {
    const gComp = (a.groupId || "").localeCompare(b.groupId || "");
    if (gComp !== 0) return gComp;
    return (a.optionId || "").localeCompare(b.optionId || "");
  });
  const tokens = sorted.map((o) => `${o.groupId}:${o.optionId}`).join("|");
  return `${menuItemId}|${tokens}`;
}

/**
 * Validates request input, loads catalog data, computes authoritative pricing,
 * and constructs the verified order document.
 * 
 * @param {FirebaseFirestore.Firestore} db - Firestore instance
 * @param {object} authContext - { uid, token, phone } from verified Firebase Auth
 * @param {object} requestData - untrusted client payload
 * @param {object} [options] - execution options (now, orderId, skipPersistence)
 * @returns {Promise<object>} { orderId, order }
 */
async function processServerAuthoritativeOrder(db, authContext, requestData, options = {}) {
  // ─── 1. Authenticate Customer Identity ─────────────────────────────────────
  if (!authContext || typeof authContext.uid !== "string" || authContext.uid.trim().length === 0) {
    const err = new Error("Unauthenticated: Customer authentication is required to place an order.");
    err.code = "unauthenticated";
    err.status = 401;
    throw err;
  }
  const canonicalCustomerId = authContext.uid.trim();

  if (!requestData || typeof requestData !== "object") {
    const err = new Error("Invalid request payload: expected an object.");
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }

  // Reject client-supplied orderId (Phase 4.1 Hardening: Order Identity Authority)
  if (
    requestData.orderId !== undefined &&
    requestData.orderId !== null &&
    String(requestData.orderId).trim().length > 0
  ) {
    const err = new Error(
      "Client-supplied orderId is strictly prohibited. Order identity is server-authoritative."
    );
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }

  // Reject spoofed / conflicting customerId
  if (requestData.customerId && typeof requestData.customerId === "string") {
    if (requestData.customerId.trim() !== canonicalCustomerId) {
      const err = new Error(
        `Unauthorized: Conflicting customerId "${requestData.customerId}" does not match authenticated user "${canonicalCustomerId}".`
      );
      err.code = "permission-denied";
      err.status = 403;
      throw err;
    }
  }

  // ─── 2. Validate Shop Identity ─────────────────────────────────────────────
  const shopId = typeof requestData.shopId === "string" ? requestData.shopId.trim() : "";
  if (!shopId) {
    const err = new Error("Invalid request: shopId is required.");
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }

  const shopDoc = await db.collection("shops").doc(shopId).get();
  if (!shopDoc.exists) {
    const err = new Error(`Shop with ID "${shopId}" does not exist.`);
    err.code = "not-found";
    err.status = 404;
    throw err;
  }

  const shopData = shopDoc.data() || {};
  if (shopData.isActive === false) {
    const err = new Error(`Shop "${shopData.name || shopId}" is currently inactive/closed.`);
    err.code = "failed-precondition";
    err.status = 400;
    throw err;
  }

  const authoritativeShopName = shopData.name || "Shop";
  const authoritativeDeliveryCharges = typeof shopData.deliveryCharges === "number"
    ? Math.max(0, shopData.deliveryCharges)
    : (typeof shopData.delivery_charges === "number" ? Math.max(0, shopData.delivery_charges) : 0);

  // ─── 3. Validate Requested Items & Enforce Cost Efficiency ─────────────────
  const rawItems = requestData.items;
  if (!Array.isArray(rawItems) || rawItems.length === 0) {
    const err = new Error("Invalid request: items must be a non-empty array.");
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }

  // Read efficiency: Deduplicate catalog menu item lookups
  const uniqueItemIds = [...new Set(rawItems.map((it) => (it && typeof it.menuItemId === "string" ? it.menuItemId.trim() : "")))];
  if (uniqueItemIds.some((id) => !id)) {
    const err = new Error("Invalid request: Each item must specify a valid menuItemId.");
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }

  const catalogItemDocs = new Map();
  await Promise.all(
    uniqueItemIds.map(async (menuItemId) => {
      const docSnap = await db.collection("shops").doc(shopId).collection("menuItems").doc(menuItemId).get();
      catalogItemDocs.set(menuItemId, docSnap);
    })
  );

  // ─── 4. Process Each Item with Authoritative Catalog & Option Pricing ──────
  const processedItems = [];
  let totalItemCount = 0;
  let calculatedSubtotal = 0;

  for (let idx = 0; idx < rawItems.length; idx++) {
    const reqItem = rawItems[idx];
    const menuItemId = reqItem.menuItemId.trim();
    const quantity = reqItem.quantity;

    // Validate quantity: integer between 1 and 99
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 99) {
      const err = new Error(
        `Invalid quantity "${quantity}" for item "${menuItemId}". Quantity must be an integer between 1 and 99.`
      );
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }

    const docSnap = catalogItemDocs.get(menuItemId);
    if (!docSnap || !docSnap.exists) {
      const err = new Error(`Menu item "${menuItemId}" not found in shop "${shopId}".`);
      err.code = "not-found";
      err.status = 404;
      throw err;
    }

    const menuData = docSnap.data() || {};

    // Validate shop tenancy
    if (menuData.shopId && menuData.shopId !== shopId) {
      const err = new Error(`Menu item "${menuItemId}" does not belong to shop "${shopId}".`);
      err.code = "failed-precondition";
      err.status = 400;
      throw err;
    }

    // Validate availability
    if (menuData.isAvailable === false) {
      const err = new Error(`Menu item "${menuData.name || menuItemId}" is currently out of stock / unavailable.`);
      err.code = "failed-precondition";
      err.status = 400;
      throw err;
    }

    // Compute Authoritative Unit Price and Options
    let itemUnitPrice = 0;
    let hasAnyFixed = false;
    const authoritativeSelectedOptions = [];
    const optionsDescriptionTokens = [];

    const reqOptions = Array.isArray(reqItem.selectedOptions) ? reqItem.selectedOptions : [];
    const catalogOptionGroups = Array.isArray(menuData.optionGroups) ? menuData.optionGroups : [];

    if (catalogOptionGroups.length === 0 && reqOptions.length > 0) {
      const err = new Error(`Menu item "${menuItemId}" does not accept option selections.`);
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }

    if (catalogOptionGroups.length > 0) {
      for (const reqOpt of reqOptions) {
        if (!reqOpt || typeof reqOpt !== "object") {
          const err = new Error("Malformed selectedOption entry.");
          err.code = "invalid-argument";
          err.status = 400;
          throw err;
        }
        const groupId = reqOpt.groupId;
        const optionId = reqOpt.optionId;
        if (!groupId || !optionId) {
          const err = new Error("Each selectedOption must contain valid groupId and optionId.");
          err.code = "invalid-argument";
          err.status = 400;
          throw err;
        }

        const group = catalogOptionGroups.find((g) => g.id === groupId);
        if (!group) {
          const err = new Error(`Invalid option group "${groupId}" does not exist for menu item "${menuItemId}".`);
          err.code = "invalid-argument";
          err.status = 400;
          throw err;
        }

        const catalogOpt = (group.options || []).find((o) => o.id === optionId);
        if (!catalogOpt) {
          const err = new Error(`Invalid option "${optionId}" does not exist in group "${groupId}" for item "${menuItemId}".`);
          err.code = "invalid-argument";
          err.status = 400;
          throw err;
        }

        const pricingType = catalogOpt.pricingType || (group.groupType === "fixed" ? "fixedPrice" : "priceAdjustment");
        const catalogOptPrice = pricingType === "selectionOnly"
          ? 0
          : (typeof catalogOpt.price === "number" ? Math.max(0, catalogOpt.price) : 0);

        if (group.groupType === "fixed" || pricingType === "fixedPrice") {
          hasAnyFixed = true;
          itemUnitPrice += catalogOptPrice;
        } else {
          itemUnitPrice += catalogOptPrice;
        }

        authoritativeSelectedOptions.push({
          groupId: group.id,
          groupName: group.name || "",
          optionId: catalogOpt.id,
          optionName: catalogOpt.name || "",
          pricingType: pricingType,
          price: catalogOptPrice,
        });
        if (catalogOpt.name) {
          optionsDescriptionTokens.push(catalogOpt.name);
        }
      }

      // Validate required groups
      for (const group of catalogOptionGroups) {
        if (group.required === true || group.groupType === "fixed") {
          const hasSelection = authoritativeSelectedOptions.some((o) => o.groupId === group.id);
          if (!hasSelection) {
            const err = new Error(`Missing required option selection for group "${group.name || group.id}".`);
            err.code = "invalid-argument";
            err.status = 400;
            throw err;
          }
        }
      }

      if (!hasAnyFixed) {
        const baseCatalogPrice = typeof menuData.price === "number" ? Math.max(0, menuData.price) : 0;
        itemUnitPrice += baseCatalogPrice;
      }

      if (itemUnitPrice <= 0) {
        itemUnitPrice = (typeof menuData.startingPrice === "number" && menuData.startingPrice > 0)
          ? menuData.startingPrice
          : (typeof menuData.price === "number" ? Math.max(0, menuData.price) : 0);
      }
    } else {
      // Standard item with no option groups
      itemUnitPrice = typeof menuData.price === "number" ? Math.max(0, menuData.price) : 0;
    }

    const itemSubtotal = itemUnitPrice * quantity;
    calculatedSubtotal += itemSubtotal;
    totalItemCount += quantity;

    processedItems.push({
      itemId: menuItemId,
      menuItemId: menuItemId,
      name: menuData.name || "Item",
      price: itemUnitPrice,
      quantity: quantity,
      subtotal: itemSubtotal,
      imageUrl: menuData.imageUrl || "",
      optionsDescription: optionsDescriptionTokens.join(" · "),
      selectedOptions: authoritativeSelectedOptions,
      cartKey: buildDeterministicCartKey(menuItemId, authoritativeSelectedOptions),
    });
  }

  // ─── 5. Calculate Authoritative Financials ──────────────────────────────────
  const grandTotal = calculatedSubtotal + authoritativeDeliveryCharges;
  const totalAmount = grandTotal;

  // ─── 6. Derive Customer Details ────────────────────────────────────────────
  let customerName = "Student";
  let customerPhone = "";

  if (authContext.token && typeof authContext.token.phone_number === "string") {
    customerPhone = authContext.token.phone_number;
  } else if (typeof authContext.phone === "string") {
    customerPhone = authContext.phone;
  }

  try {
    const userDoc = await db.collection("users").doc(canonicalCustomerId).get();
    if (userDoc.exists) {
      const userData = userDoc.data() || {};
      if (userData.name && typeof userData.name === "string" && userData.name.trim().length > 0) {
        customerName = userData.name.trim();
      }
      if (userData.phone && typeof userData.phone === "string" && userData.phone.trim().length > 0) {
        customerPhone = userData.phone.trim();
      }
    }
  } catch (_) {}

  // Fallback to request metadata if user record was incomplete, with sanitization
  if (customerName === "Student" && typeof requestData.customerName === "string" && requestData.customerName.trim().length > 0) {
    customerName = requestData.customerName.trim().slice(0, 100);
  }
  if (!customerPhone && typeof requestData.customerPhone === "string" && requestData.customerPhone.trim().length > 0) {
    customerPhone = requestData.customerPhone.trim().slice(0, 20);
  }

  const specialInstructions = typeof requestData.specialInstructions === "string"
    ? requestData.specialInstructions.trim().slice(0, 500)
    : "";
  const deliveryNote = typeof requestData.deliveryNote === "string" && requestData.deliveryNote.trim().length > 0
    ? requestData.deliveryNote.trim().slice(0, 200)
    : (shopData.deliveryNote || "Bennett University");

  const orderMethod = requestData.orderMethod === "whatsapp" ? "whatsapp" : "app";

  // ─── 7. Timestamps and Lifecycle Deadlines ──────────────────────────────────
  const now = options.now instanceof Date ? options.now : new Date();
  const acceptDeadlineDate = new Date(now.getTime() + 20 * 60 * 1000); // 20 minutes

  // Server-Authoritative orderId generation:
  // Strictly generated by the server backend.
  // Note: options._serverOrderId is reserved strictly for internal test harnesses (e.g. collision testing)
  let orderId;
  if (typeof options._serverOrderId === "string" && options._serverOrderId.trim().length > 0) {
    orderId = options._serverOrderId.trim();
  } else {
    const randomHex = crypto.randomBytes(6).toString("hex").toUpperCase();
    orderId = `ORD_${now.getTime()}_${randomHex}`;
  }

  // ─── 8. Construct Final Authoritative Order Document ───────────────────────
  const createdAtTimestamp = options.now ? Timestamp.fromDate(now) : FieldValue.serverTimestamp();
  const updatedAtTimestamp = options.now ? Timestamp.fromDate(now) : FieldValue.serverTimestamp();

  const finalOrderDoc = {
    orderId,
    shopId,
    shopName: authoritativeShopName,
    customerId: canonicalCustomerId,
    customerName,
    customerPhone,
    items: processedItems,
    subtotal: calculatedSubtotal,
    deliveryCharges: authoritativeDeliveryCharges,
    totalItems: totalItemCount,
    grandTotal: grandTotal,
    totalAmount: totalAmount,
    specialInstructions,
    deliveryNote,
    status: "placed",
    rejectionReason: "",
    orderMethod,
    createdAt: createdAtTimestamp,
    updatedAt: updatedAtTimestamp,
    acceptDeadline: Timestamp.fromDate(acceptDeadlineDate),
  };

  // ─── 9. Atomic Persistence in Firestore ────────────────────────────────────
  // Eliminates check-then-write race condition by using native atomic create() or isolated transaction.
  if (options.skipPersistence !== true) {
    const docRef = db.collection("orders").doc(orderId);
    try {
      if (typeof docRef.create === "function") {
        // Native Firestore Admin SDK atomic create:
        // Fails with ALREADY_EXISTS (code 6) if document already exists.
        await docRef.create(finalOrderDoc);
      } else {
        // Atomic transaction fallback
        await db.runTransaction(async (t) => {
          const snap = await t.get(docRef);
          if (snap.exists) {
            const err = new Error(`Order collision: document with ID "${orderId}" already exists.`);
            err.code = 6;
            err.status = 409;
            throw err;
          }
          t.set(docRef, finalOrderDoc);
        });
      }
    } catch (createErr) {
      if (
        createErr.code === 6 ||
        createErr.code === "already-exists" ||
        (createErr.message && createErr.message.toLowerCase().includes("already exists"))
      ) {
        const err = new Error(`Order collision: document with ID "${orderId}" already exists. Overwrite prohibited.`);
        err.code = "already-exists";
        err.status = 409;
        throw err;
      }
      throw createErr;
    }
  }

  return {
    success: true,
    orderId,
    order: finalOrderDoc,
  };
}

module.exports = {
  processServerAuthoritativeOrder,
  buildDeterministicCartKey,
};
