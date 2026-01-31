// Update Tenant Code in Firebase
const admin = require('firebase-admin');
const serviceAccount = require('./web-app-sadara-firebase-adminsdk-fbsvc-b1c405cb4d.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'web-app-sadara'
});

const db = admin.firestore();

async function updateTenantCode() {
  try {
    console.log('Updating tenant code...');
    
    // Update the tenant with ID 'demo001'
    await db.collection('tenants').doc('demo001').update({
      code: 'DEMO001'
    });
    
    console.log('✅ Tenant code updated successfully!');
    console.log('   Old code: اهلا');
    console.log('   New code: DEMO001');
    console.log('');
    console.log('Now you can login with:');
    console.log('   Tenant Code: DEMO001');
    console.log('   Username: 123456 or 1');
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
  
  process.exit(0);
}

updateTenantCode();
