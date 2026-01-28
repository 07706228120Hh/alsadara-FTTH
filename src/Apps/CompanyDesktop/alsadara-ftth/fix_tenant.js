const admin = require('firebase-admin');

// تهيئة Firebase Admin
const serviceAccount = require('./firebase-service-account.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixTenantData() {
  try {
    console.log('🔧 إصلاح بيانات الشركة demo001...\n');
    
    // تحديث/إضافة بيانات الشركة
    await db.collection('tenants').doc('demo001').set({
      name: 'شركة تجريبية',
      code: 'اهلا',
      address: 'الرياض، المملكة العربية السعودية',
      phone: '+966500000000',
      email: 'demo@example.com',
      isActive: true,
      maxUsers: 50,
      subscriptionPlan: 'yearly',
      subscriptionStart: admin.firestore.Timestamp.now(),
      subscriptionEnd: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 365 * 24 * 60 * 60 * 1000)),
      createdAt: admin.firestore.Timestamp.now(),
      createdBy: 'system',
      logo: null
    }, { merge: true });
    
    console.log('✅ تم إضافة/تحديث بيانات الشركة!\n');
    
    // التحقق
    const doc = await db.collection('tenants').doc('demo001').get();
    console.log('📄 بيانات الشركة الآن:');
    console.log(JSON.stringify(doc.data(), null, 2));
    
    // فحص المستخدمين
    const usersSnap = await db.collection('tenants').doc('demo001').collection('users').get();
    console.log(`\n👥 عدد المستخدمين: ${usersSnap.size}`);
    
  } catch (error) {
    console.error('❌ خطأ:', error.message);
  } finally {
    process.exit();
  }
}

fixTenantData();
