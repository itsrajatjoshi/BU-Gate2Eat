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
 * Limits for abuse prevention and physical/monetary constraints:
 * - MAX_ITEMS_PER_ORDER: 50 line items. Prevents unbounded array processing / memory DoS.
 * - MAX_ITEM_QUANTITY: 99 per item. Matches Flutter model clamp(1, 99).
 * - MAX_TOTAL_QUANTITY: 500 total units. Prevents physical fulfillment impossibility / inventory denial of service.
 * - MAX_ITEM_PRICE: 100,000 INR (1 Lakh). Matches Flutter model clamp(0, 100000).
 * - MAX_ORDER_GRAND_TOTAL: 500,000 INR (5 Lakhs). Standard payment gateway single-transaction ceiling in India.
 */
const MAX_ITEMS_PER_ORDER = 50;
const MAX_ITEM_QUANTITY = 99;
const MAX_TOTAL_QUANTITY = 500;
const MAX_ITEM_PRICE = 100000;
const MAX_ORDER_GRAND_TOTAL = 500000;

/**
 * Converts INR rupees to integer paise (minor units).
 * Guarantees exact integer arithmetic and eliminates floating point drift.
 *
 * @param {number} rupees
 * @returns {number} integer paise
 */
function toPaise(rupees) {
  if (typeof rupees !== "number" || !Number.isFinite(rupees)) {
    throw new Error(`Invalid monetary amount: ${rupees}`);
  }
  return Math.round(rupees * 100);
}

/**
 * Converts integer paise back to INR rupees (decimal representation).
 *
 * @param {number} paise
 * @returns {number} rupees
 */
function fromPaise(paise) {
  if (!Number.isInteger(paise)) {
    throw new Error(`Expected integer paise amount, got ${paise}`);
  }
  return paise / 100;
}

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

  // ─── 2. Validate Shop Identity & Authoritative Delivery Charges ────────────
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
  const rawDelivery = typeof shopData.deliveryCharges === "number"
    ? shopData.deliveryCharges
    : (typeof shopData.delivery_charges === "number" ? shopData.delivery_charges : (shopData.deliveryCharges ?? shopData.delivery_charges ?? 0));

  if (typeof rawDelivery !== "number" || !Number.isFinite(rawDelivery) || rawDelivery < 0) {
    const err = new Error(`Catalog error: Shop "${shopId}" has invalid or negative delivery charges (${rawDelivery}).`);
    err.code = "failed-precondition";
    err.status = 400;
    throw err;
  }
  const deliveryChargesPaise = toPaise(rawDelivery);
  const authoritativeDeliveryCharges = fromPaise(deliveryChargesPaise);

  // ─── 3. Validate Requested Items & Enforce Cost Efficiency ─────────────────
  const rawItems = requestData.items;
  if (!Array.isArray(rawItems) || rawItems.length === 0) {
    const err = new Error("Invalid request: items must be a non-empty array.");
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }

  if (rawItems.length > MAX_ITEMS_PER_ORDER) {
    const err = new Error(
      `Invalid request: Order cannot contain more than ${MAX_ITEMS_PER_ORDER} distinct items (received ${rawItems.length}).`
    );
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
  let calculatedSubtotalPaise = 0;

  for (let idx = 0; idx < rawItems.length; idx++) {
    const reqItem = rawItems[idx];
    if (!reqItem || typeof reqItem !== "object") {
      const err = new Error(`Invalid item payload at index ${idx}.`);
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }

    const menuItemId = typeof reqItem.menuItemId === "string" ? reqItem.menuItemId.trim() : "";
    const quantity = reqItem.quantity;

    // Validate quantity: integer between 1 and MAX_ITEM_QUANTITY (99)
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > MAX_ITEM_QUANTITY) {
      const err = new Error(
        `Invalid quantity "${quantity}" for item "${menuItemId}". Quantity must be an integer between 1 and ${MAX_ITEM_QUANTITY}.`
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

    // Validate authoritative base catalog price (No silent clamping)
    const rawBasePrice = menuData.price;
    if (typeof rawBasePrice !== "number" || !Number.isFinite(rawBasePrice) || rawBasePrice < 0) {
      const err = new Error(`Catalog error: Menu item "${menuItemId}" has invalid or negative price (${rawBasePrice}).`);
      err.code = "failed-precondition";
      err.status = 400;
      throw err;
    }
    const basePricePaise = toPaise(rawBasePrice);

    let startingPricePaise = 0;
    if (menuData.startingPrice !== undefined && menuData.startingPrice !== null) {
      if (typeof menuData.startingPrice !== "number" || !Number.isFinite(menuData.startingPrice) || menuData.startingPrice < 0) {
        const err = new Error(`Catalog error: Menu item "${menuItemId}" has invalid startingPrice (${menuData.startingPrice}).`);
        err.code = "failed-precondition";
        err.status = 400;
        throw err;
      }
      startingPricePaise = toPaise(menuData.startingPrice);
    }

    // Compute Authoritative Unit Price and Options
    let unitPricePaise = 0;
    let hasAnyFixed = false;
    const authoritativeSelectedOptions = [];
    const optionsDescriptionTokens = [];

    const reqOptions = Array.isArray(reqItem.selectedOptions) ? reqItem.selectedOptions : [];
    const catalogOptionGroups = Array.isArray(menuData.optionGroups)
      ? menuData.optionGroups
      : (Array.isArray(menuData.groups) ? menuData.groups : []);

    if (catalogOptionGroups.length === 0 && reqOptions.length > 0) {
      const err = new Error(`Menu item "${menuItemId}" does not accept option selections.`);
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }

    if (catalogOptionGroups.length > 0) {
      // Map to collect requested selections per option group
      const selectionsByGroup = new Map();
      const seenOptionKeys = new Set();

      for (const reqOpt of reqOptions) {
        if (!reqOpt || typeof reqOpt !== "object") {
          const err = new Error("Malformed selectedOption entry.");
          err.code = "invalid-argument";
          err.status = 400;
          throw err;
        }
        const groupId = typeof reqOpt.groupId === "string" ? reqOpt.groupId.trim() : "";
        const optionId = typeof reqOpt.optionId === "string" ? reqOpt.optionId.trim() : "";
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

        // Prevent duplicate selection of the exact same optionId within a group
        const optKey = `${groupId}:${optionId}`;
        if (seenOptionKeys.has(optKey)) {
          const err = new Error(`Duplicate selection of option "${optionId}" in group "${groupId}".`);
          err.code = "invalid-argument";
          err.status = 400;
          throw err;
        }
        seenOptionKeys.add(optKey);

        // Authoritative option pricing validation (Mandatory Correction 1: No silent clamping)
        const pricingType = catalogOpt.pricingType || (group.groupType === "fixed" ? "fixedPrice" : "priceAdjustment");
        let catalogOptPricePaise = 0;

        if (pricingType !== "selectionOnly") {
          const rawOptPrice = catalogOpt.price;
          if (typeof rawOptPrice !== "number" || !Number.isFinite(rawOptPrice) || rawOptPrice < 0) {
            const err = new Error(
              `Catalog error: Option "${optionId}" in group "${groupId}" has invalid or negative price (${rawOptPrice}).`
            );
            err.code = "failed-precondition";
            err.status = 400;
            throw err;
          }
          catalogOptPricePaise = toPaise(rawOptPrice);
        }

        if (!selectionsByGroup.has(groupId)) {
          selectionsByGroup.set(groupId, []);
        }
        selectionsByGroup.get(groupId).push({
          group,
          catalogOpt,
          pricingType,
          catalogOptPricePaise,
        });
      }

      // Validate group-level selection constraints according to authoritative catalog schema (Mandatory Correction 2)
      for (const group of catalogOptionGroups) {
        const selections = selectionsByGroup.get(group.id) || [];
        const count = selections.length;

        const isMulti = group.multiple === true || group.allowMultiple === true || (typeof group.maxSelections === "number" && group.maxSelections > 1);

        let minSelections;
        let maxSelections;

        if (typeof group.minSelections === "number") {
          minSelections = group.minSelections;
        } else if (group.required === true || group.groupType === "fixed") {
          minSelections = 1;
        } else {
          minSelections = 0;
        }

        if (typeof group.maxSelections === "number") {
          maxSelections = group.maxSelections;
        } else if (isMulti) {
          maxSelections = Array.isArray(group.options) ? group.options.length : 10;
        } else {
          maxSelections = 1;
        }

        if (count < minSelections) {
          const err = new Error(
            `Missing required option selection for group "${group.name || group.id}". Expected at least ${minSelections}, got ${count}.`
          );
          err.code = "invalid-argument";
          err.status = 400;
          throw err;
        }

        if (count > maxSelections) {
          const err = new Error(
            `Too many options selected for group "${group.name || group.id}". Maximum allowed is ${maxSelections}, got ${count}.`
          );
          err.code = "invalid-argument";
          err.status = 400;
          throw err;
        }

        // Accumulate option pricing and tokens
        for (const sel of selections) {
          if (group.groupType === "fixed" || sel.pricingType === "fixedPrice") {
            hasAnyFixed = true;
          }
          unitPricePaise += sel.catalogOptPricePaise;

          authoritativeSelectedOptions.push({
            groupId: group.id,
            groupName: group.name || "",
            optionId: sel.catalogOpt.id,
            optionName: sel.catalogOpt.name || "",
            pricingType: sel.pricingType,
            price: fromPaise(sel.catalogOptPricePaise),
          });

          if (sel.catalogOpt.name) {
            optionsDescriptionTokens.push(sel.catalogOpt.name);
          }
        }
      }

      if (!hasAnyFixed) {
        unitPricePaise += basePricePaise;
      }

      if (unitPricePaise <= 0) {
        unitPricePaise = startingPricePaise > 0 ? startingPricePaise : basePricePaise;
      }
    } else {
      // Standard item with no option groups
      unitPricePaise = basePricePaise;
    }

    // Check item unit price ceiling
    if (unitPricePaise > toPaise(MAX_ITEM_PRICE)) {
      const err = new Error(
        `Item unit price for "${menuItemId}" (₹${fromPaise(unitPricePaise)}) exceeds allowable maximum limit of ₹${MAX_ITEM_PRICE}.`
      );
      err.code = "invalid-argument";
      err.status = 400;
      throw err;
    }

    const itemSubtotalPaise = unitPricePaise * quantity;
    calculatedSubtotalPaise += itemSubtotalPaise;
    totalItemCount += quantity;

    processedItems.push({
      itemId: menuItemId,
      menuItemId: menuItemId,
      name: menuData.name || "Item",
      price: fromPaise(unitPricePaise),
      quantity: quantity,
      subtotal: fromPaise(itemSubtotalPaise),
      imageUrl: menuData.imageUrl || "",
      optionsDescription: optionsDescriptionTokens.join(" · "),
      selectedOptions: authoritativeSelectedOptions,
      cartKey: buildDeterministicCartKey(menuItemId, authoritativeSelectedOptions),
    });
  }

  // Validate total order quantity ceiling
  if (totalItemCount > MAX_TOTAL_QUANTITY) {
    const err = new Error(
      `Total item quantity across all order items (${totalItemCount}) exceeds allowable limit of ${MAX_TOTAL_QUANTITY}.`
    );
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }

  // ─── 5. Calculate Authoritative Financials (Paise Minor Units) ──────────────
  const grandTotalPaise = calculatedSubtotalPaise + deliveryChargesPaise;
  if (grandTotalPaise > toPaise(MAX_ORDER_GRAND_TOTAL)) {
    const err = new Error(
      `Order grand total (₹${fromPaise(grandTotalPaise)}) exceeds allowable maximum limit of ₹${MAX_ORDER_GRAND_TOTAL}.`
    );
    err.code = "invalid-argument";
    err.status = 400;
    throw err;
  }

  const calculatedSubtotal = fromPaise(calculatedSubtotalPaise);
  const grandTotal = fromPaise(grandTotalPaise);
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
  toPaise,
  fromPaise,
  MAX_ITEMS_PER_ORDER,
  MAX_ITEM_QUANTITY,
  MAX_TOTAL_QUANTITY,
  MAX_ITEM_PRICE,
  MAX_ORDER_GRAND_TOTAL,
};
