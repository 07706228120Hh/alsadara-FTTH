// Restore Arabic Tenant Code
const admin = require('firebase-admin');
const serviceAccount = require('./web-app-sadara-firebase-adminsdk-fbsvc-b1c405cb4d.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'web-app-sadara'
});

const db = admin.firestore();

async function restoreArabicCode() {
  try {
    console.log('Restoring Arabic tenant code...');
    
    await db.collection('tenants').doc('demo001').update({
      code: 'اهلا'
    });
    
    console.log('✅ Tenant code restored!');
    console.log('   Code: اهلا');
    console.log('');
    console.log('Now you can login with:');
    console.log('   Tenant Code: اهلا');
    console.log('   Username: 123456 or 1');
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
  
  process.exit(0);
}

restoreArabicCode();
