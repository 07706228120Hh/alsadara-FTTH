const admin = require('firebase-admin');

// تهيئة Firebase Admin
const serviceAccount = require('./firebase-service-account.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkUsers() {
  try {
    const tenantId = 'demo001';
    
    console.log('🔍 التحقق من المستخدمين في Firebase...');
    console.log('');
    
    const usersSnapshot = await db.collection('tenants')
      .doc(tenantId)
      .collection('users')
      .get();
    
    console.log(`📊 عدد المستخدمين: ${usersSnapshot.size}`);
    console.log('');
    
    if (usersSnapshot.size > 0) {
      console.log('👥 قائمة المستخدمين:');
      console.log('');
      usersSnapshot.docs.forEach((doc, index) => {
        const data = doc.data();
        console.log(`${index + 1}. ${data.fullName}`);
        console.log(`   - ID: ${doc.id}`);
        console.log(`   - اسم المستخدم: ${data.username}`);
        console.log(`   - الكود: ${data.code || 'غير محدد'}`);
        console.log(`   - الهاتف: ${data.phone || 'غير محدد'}`);
        console.log(`   - الدور: ${data.role}`);
        console.log(`   - القسم: ${data.department || 'غير محدد'}`);
        console.log(`   - المركز: ${data.center || 'غير محدد'}`);
        console.log(`   - الراتب: ${data.salary || 'غير محدد'}`);
        console.log(`   - نشط: ${data.isActive ? 'نعم' : 'لا'}`);
        console.log('');
      });
    } else {
      console.log('❌ لا يوجد مستخدمين في القاعدة!');
    }
    
  } catch (error) {
    console.error('❌ حدث خطأ:', error);
  } finally {
    process.exit();
  }
}

checkUsers();
