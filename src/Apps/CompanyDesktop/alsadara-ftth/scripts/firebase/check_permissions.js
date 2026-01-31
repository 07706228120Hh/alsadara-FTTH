// Check User Permissions in Firebase
const admin = require('firebase-admin');
const serviceAccount = require('./web-app-sadara-firebase-adminsdk-fbsvc-b1c405cb4d.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'web-app-sadara'
});

const db = admin.firestore();

async function checkUserPermissions() {
  try {
    console.log('============================================================');
    console.log('Checking User Permissions in Firebase');
    console.log('============================================================\n');

    // Get the tenant
    const tenantDoc = await db.collection('tenants').doc('demo001').get();
    const tenant = tenantDoc.data();
    
    console.log('Tenant:', tenant.name);
    console.log('Tenant Code:', tenant.code);
    console.log('\n');

    // Get users
    const usersSnapshot = await db.collection('tenants').doc('demo001').collection('users').get();
    
    console.log(`Found ${usersSnapshot.size} users:\n`);
    
    usersSnapshot.forEach(doc => {
      const user = doc.data();
      console.log('─'.repeat(60));
      console.log(`User ID: ${doc.id}`);
      console.log(`Username: ${user.username || 'N/A'}`);
      console.log(`Full Name: ${user.fullName || user.name || 'N/A'}`);
      console.log(`Role: ${user.role || 'N/A'}`);
      console.log(`Active: ${user.isActive !== false ? 'Yes' : 'No'}`);
      console.log('\nPermissions Structure:');
      console.log(JSON.stringify({
        firstSystemPermissions: user.firstSystemPermissions || {},
        secondSystemPermissions: user.secondSystemPermissions || {},
        permissions: user.permissions || {}
      }, null, 2));
      console.log('');
    });

    console.log('============================================================');
    console.log('Analysis:');
    console.log('============================================================');
    
    const sampleUser = usersSnapshot.docs[0]?.data();
    if (sampleUser) {
      if (!sampleUser.firstSystemPermissions || Object.keys(sampleUser.firstSystemPermissions).length === 0) {
        console.log('⚠️  firstSystemPermissions is missing or empty!');
      } else {
        console.log('✓ firstSystemPermissions exists');
      }
      
      if (!sampleUser.secondSystemPermissions || Object.keys(sampleUser.secondSystemPermissions).length === 0) {
        console.log('⚠️  secondSystemPermissions is missing or empty!');
      } else {
        console.log('✓ secondSystemPermissions exists');
      }
      
      if (sampleUser.permissions && Object.keys(sampleUser.permissions).length > 0) {
        console.log('ℹ️  Old "permissions" field exists - needs migration');
      }
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
  
  process.exit(0);
}

checkUserPermissions();
