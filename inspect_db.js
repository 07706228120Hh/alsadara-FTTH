const admin = require('firebase-admin');

// تهيئة Firebase Admin
const serviceAccount = require('./firebase-service-account.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function listAllCollections() {
  try {
    console.log('🔍 فحص هيكل قاعدة البيانات...\n');
    
    // فحص demo001 document
    const tenantDoc = await db.collection('tenants').doc('demo001').get();
    console.log('📄 بيانات الشركة (demo001):');
    console.log(JSON.stringify(tenantDoc.data(), null, 2));
    console.log('');
    
    // فحص subcollections داخل demo001
    const subcollections = await db.collection('tenants').doc('demo001').listCollections();
    console.log('📁 المجموعات الفرعية داخل demo001:');
    for (const coll of subcollections) {
      console.log(`   - ${coll.id}`);
      const docs = await coll.get();
      console.log(`     (${docs.size} documents)`);
    }
    console.log('');
    
    // فحص users subcollection
    const usersSnapshot = await db.collection('tenants').doc('demo001').collection('users').get();
    console.log(`👥 المستخدمين (${usersSnapshot.size}):`);
    usersSnapshot.docs.forEach((doc, i) => {
      const data = doc.data();
      console.log(`\n${i+1}. ${data.username || 'بدون اسم'}`);
      console.log(`   fullName: ${data.fullName || 'غير محدد'}`);
      console.log(`   code: ${data.code || 'غير محدد'}`);
    });
    
  } catch (error) {
    console.error('❌ خطأ:', error.message);
  } finally {
    process.exit();
  }
}

listAllCollections();
