// server/tools/seed_nutrition_data.js
import 'dotenv/config';
import admin from 'firebase-admin';
import fs from 'node:fs';

function buildCredentialFromEnv() {
  // Option A: FIREBASE_SERVICE_ACCOUNT is a full JSON string
  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    const json = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    return { cred: admin.credential.cert(json), projectId: json.project_id };
  }

  // Option B: individual fields in .env
  const projectId = process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  let privateKey = process.env.FIREBASE_PRIVATE_KEY;

  if (projectId && clientEmail && privateKey) {
    // fix escaped newlines from .env
    privateKey = privateKey.replace(/\\n/g, '\n');
    return {
      cred: admin.credential.cert({ projectId, clientEmail, privateKey }),
      projectId,
    };
  }

  // Option C: Application Default Credentials + explicit project id hint
  // (GOOGLE_APPLICATION_CREDENTIALS should point to a file, and we try to read project_id)
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    try {
      const raw = fs.readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8');
      const json = JSON.parse(raw);
      return { cred: admin.credential.applicationDefault(), projectId: json.project_id };
    } catch {
      // fall through; ADC may still work if GOOGLE_CLOUD_PROJECT is set
      return { cred: admin.credential.applicationDefault(), projectId: process.env.GOOGLE_CLOUD_PROJECT };
    }
  }

  // Last resort: ADC with GOOGLE_CLOUD_PROJECT / GCLOUD_PROJECT / FIREBASE_CONFIG
  const pid = process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT;
  return { cred: admin.credential.applicationDefault(), projectId: pid };
}

// Initialize Admin once
if (!admin.apps.length) {
  const { cred, projectId } = buildCredentialFromEnv();
  if (!projectId) {
    console.error('Firebase init failed: no projectId found. Set FIREBASE_PROJECT_ID (or include project_id in your service account JSON), or set GOOGLE_CLOUD_PROJECT.');
    process.exit(1);
  }

  admin.initializeApp({
    credential: cred,
    projectId, // <- ensures Admin SDK knows the project
  });
}

const db = admin.firestore();
