// Firebase Admin SDK - Read Firestore Data
// npm install firebase-admin

const admin = require('firebase-admin');
const serviceAccount = require('./web-app-sadara-firebase-adminsdk-fbsvc-b1c405cb4d.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'web-app-sadara'
});

const db = admin.firestore();

async function readAllData() {
  console.log('='.repeat(60));
  console.log('Connected to Firebase Project: web-app-sadara');
  console.log('='.repeat(60));
  console.log('');

  try {
    // Read Super Admins
    console.log('📋 SUPER ADMINS:');
    console.log('-'.repeat(60));
    const superAdmins = await db.collection('super_admins').get();
    
    if (superAdmins.empty) {
      console.log('  ⚠️  No super admins found');
    } else {
      superAdmins.forEach(doc => {
        const data = doc.data();
        console.log(`  ✓ ID: ${doc.id}`);
        console.log(`    Username: ${data.username || 'N/A'}`);
        console.log(`    Name: ${data.name || 'N/A'}`);
        console.log(`    Email: ${data.email || 'N/A'}`);
        console.log('');
      });
    }

    // Read Tenants
    console.log('');
    console.log('🏢 TENANTS (Companies):');
    console.log('-'.repeat(60));
    const tenants = await db.collection('tenants').get();
    
    if (tenants.empty) {
      console.log('  ⚠️  No tenants found');
    } else {
      for (const doc of tenants.docs) {
        const data = doc.data();
        console.log(`  ✓ ID: ${doc.id}`);
        console.log(`    Code: ${data.code || 'N/A'}`);
        console.log(`    Name: ${data.name || 'N/A'}`);
        console.log(`    Active: ${data.isActive !== false ? 'Yes' : 'No'}`);
        
        // Read users for this tenant
        const users = await db.collection('tenants').doc(doc.id).collection('users').get();
        console.log(`    Users: ${users.size}`);
        
        if (!users.empty) {
          users.forEach(userDoc => {
            const userData = userDoc.data();
            console.log(`      → User: ${userData.username || 'N/A'} (${userData.fullName || userData.name || 'N/A'})`);
          });
        }
        console.log('');
      }
    }

    // Read Users (if stored directly)
    console.log('');
    console.log('👤 USERS (Direct Collection):');
    console.log('-'.repeat(60));
    const users = await db.collection('users').get();
    
    if (users.empty) {
      console.log('  ⚠️  No users found in direct collection');
    } else {
      users.forEach(doc => {
        const data = doc.data();
        console.log(`  ✓ ID: ${doc.id}`);
        console.log(`    Email: ${data.email || 'N/A'}`);
        console.log(`    Name: ${data.displayName || data.name || 'N/A'}`);
        console.log(`    Role: ${data.role || 'N/A'}`);
        console.log('');
      });
    }

    console.log('='.repeat(60));
    console.log('✅ Data retrieved successfully!');
    console.log('='.repeat(60));
    
  } catch (error) {
    console.error('❌ Error reading data:', error);
  }
  
  process.exit(0);
}

// Run the script
readAllData();
