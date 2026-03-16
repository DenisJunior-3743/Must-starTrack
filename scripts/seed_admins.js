// scripts/seed_admins.js
//
// MUST StarTrack — Admin & Super Admin Seeder
//
// Usage:
//   1. Download your Firebase service account key:
//      Firebase Console → Project Settings → Service Accounts → Generate new private key
//      Save it as: scripts/serviceAccountKey.json  (never commit this file!)
//
//   2. Install dependencies (once):
//      cd scripts && npm install
//
//   3. Run:
//      node seed_admins.js
//
// What it does:
//   - Creates Firebase Auth accounts (email/password, pre-verified)
//   - Creates matching Firestore /users/{uid} documents
//   - Safe to re-run — skips accounts that already exist

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const auth = admin.auth();
const db   = admin.firestore();

// ── Default accounts ──────────────────────────────────────────────────────────
// Change these passwords immediately after first login!

const ACCOUNTS = [
  {
    email:       'admin@must.ac.ug',
    password:    'Admin@StarTrack2026!',
    displayName: 'StarTrack Admin',
    role:        'admin',
  },
  {
    email:       'superadmin@must.ac.ug',
    password:    'SuperAdmin@StarTrack2026!',
    displayName: 'StarTrack Super Admin',
    role:        'super_admin',
  },
];

// ── Seed function ─────────────────────────────────────────────────────────────

async function seedAccount(account) {
  const { email, password, displayName, role } = account;

  let uid;

  // Create Auth user (or fetch existing)
  try {
    const userRecord = await auth.createUser({
      email,
      password,
      displayName,
      emailVerified: true,   // Skip email verification gate in the app
      disabled: false,
    });
    uid = userRecord.uid;
    console.log(`✅ Created Auth user: ${email}  (uid: ${uid})`);
  } catch (err) {
    if (err.code === 'auth/email-already-exists') {
      const existing = await auth.getUserByEmail(email);
      uid = existing.uid;
      console.log(`⚠️  Auth user already exists: ${email}  (uid: ${uid})`);
    } else {
      throw err;
    }
  }

  // Create or overwrite Firestore /users/{uid}
  const now = new Date().toISOString();
  const userDoc = {
    // UserModel.fromJson() — camelCase keys
    firebaseUid:     uid,
    email,
    role,
    displayName,
    photoUrl:        null,
    isEmailVerified: true,
    isSuspended:     false,
    isBanned:        false,
    lastSeenAt:      null,
    createdAt:       now,
    updatedAt:       now,
  };

  await db.collection('users').doc(uid).set(userDoc, { merge: true });
  console.log(`✅ Firestore /users/${uid} written  (role: ${role})\n`);
}

// ── Run ───────────────────────────────────────────────────────────────────────

(async () => {
  console.log('🚀 MUST StarTrack — Seeding admin accounts...\n');
  for (const account of ACCOUNTS) {
    await seedAccount(account);
  }
  console.log('Done. Change the default passwords immediately after first login!');
  process.exit(0);
})().catch(err => {
  console.error('❌ Seed failed:', err);
  process.exit(1);
});
