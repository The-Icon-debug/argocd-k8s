namespace: user-app
│
├── ConfigMap
│     ├── PORT
│     ├── APP_NAME
│     └── MONGO_DB
│
├── Secret
│     ├── MONGO_USER
│     ├── MONGO_PASSWORD
│     ├── MONGO_URI
│     └── JWT_SECRET
│
├── MongoDB
│     │
│     ├── Deployment
│     │
│     ├── Service
│     │
│     └── PersistentVolumeClaim
│
└── Node.js
      │
      ├── Deployment
      │
      └── Service
