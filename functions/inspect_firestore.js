const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp({
  projectId: "bu-gate2eat"
});

const db = getFirestore();

async function inspectTokens() {
  console.log("=== INSPECTING deviceTokens COLLECTION ===");
  const snapshot = await db.collection("deviceTokens").get();
  console.log(`Total documents in deviceTokens: ${snapshot.size}`);
  snapshot.forEach(doc => {
    const data = doc.data();
    const tokenMasked = data.token ? `${data.token.substring(0, 8)}...${data.token.substring(data.token.length - 8)}` : "no-token";
    console.log(`Doc ID: ${doc.id}`);
    console.log(`  Token: ${tokenMasked}`);
    console.log(`  Role: ${data.role}`);
    console.log(`  Phone: ${data.phone}`);
    console.log(`  CustomerId: ${data.customerId}`);
    console.log(`  ShopId: ${data.shopId}`);
    console.log(`  Platform: ${data.platform}`);
    console.log(`  UpdatedAt: ${data.updatedAt ? data.updatedAt.toDate() : "none"}`);
  });
  
  console.log("\n=== INSPECTING RECENT ORDERS ===");
  const ordersSnap = await db.collection("orders").orderBy("createdAt", "desc").limit(5).get();
  console.log(`Recent orders count: ${ordersSnap.size}`);
  ordersSnap.forEach(doc => {
    const d = doc.data();
    console.log(`Order: ${d.orderId} | Status: ${d.status} | Shop: ${d.shopId} | Customer: ${d.customerId} | Phone: ${d.customerPhone} | Created: ${d.createdAt ? d.createdAt.toDate() : "none"}`);
  });
}

inspectTokens().catch(console.error);
