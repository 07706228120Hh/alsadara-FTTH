const admin = require('firebase-admin');

// تهيئة Firebase Admin
const serviceAccount = require('./firebase-service-account.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function listAllTenants() {
  try {
    console.log('🔍 فحص جميع الشركات في tenants...\n');
    
    const tenantsSnapshot = await db.collection('tenants').get();
    
    console.log(`📊 عدد الشركات: ${tenantsSnapshot.size}\n`);
    
    for (const doc of tenantsSnapshot.docs) {
      const data = doc.data();
      console.log(`📁 Tenant ID: ${doc.id}`);
      console.log(`   - الاسم: ${data.name || 'غير محدد'}`);
      console.log(`   - الكود: ${data.code || 'غير محدد'}`);
      console.log(`   - نشط: ${data.isActive}`);
      
      // فحص المستخدمين
      const usersSnap = await db.collection('tenants').doc(doc.id).collection('users').get();
      console.log(`   - عدد المستخدمين: ${usersSnap.size}`);
      console.log('');
    }
    
  } catch (error) {
    console.error('❌ خطأ:', error.message);
  } finally {
    process.exit();
  }
}

listAllTenants();
