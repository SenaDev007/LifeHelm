import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import rateLimit from 'express-rate-limit';
import { config } from './config.js';
import { startKeepalive } from './db.js';
import { errorHandler } from './middleware/error.js';
import authRoutes from './routes/auth.js';
import financeRoutes from './routes/finance.js';
import goalRoutes from './routes/goals.js';
import routineRoutes from './routes/routines.js';
import healthRoutes from './routes/health.js';
import accessibleRoutes from './routes/accessible.js';
import aiRoutes from './routes/ai.js';
import userRoutes from './routes/user.js';
// V2
import familyRoutes from './routes/family.js';
import subscriptionRoutes from './routes/subscriptions.js';
import notificationRoutes from './routes/notifications.js';
import exportRoutes from './routes/exports.js';
import smsImportRoutes from './routes/sms-import.js';
import syncRoutes from './routes/sync.js';

const app = express();

// Railway (et autres PaaS) routent via un proxy qui ajoute X-Forwarded-For
// Sans trust proxy, express-rate-limit crash avec ERR_ERL_UNEXPECTED_X_FORWARDED_FOR
app.set('trust proxy', 1);

app.use(helmet());
app.use(cors({
  origin: config.corsOrigin === '*' ? true : config.corsOrigin.split(','),
  credentials: true,
}));
app.use(express.json({ limit: '5mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(morgan(config.nodeEnv === 'development' ? 'dev' : 'combined'));

// Rate limiting global
app.use(rateLimit({
  windowMs: config.rateLimit.windowMs,
  max: config.rateLimit.max,
  standardHeaders: true,
  legacyHeaders: false,
}));

// Health check — affiche le hash du commit pour vérifier la version déployée
const BUILD_HASH = process.env.RAILWAY_GIT_COMMIT_SHA?.slice(0, 7) || 'local';
app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'lifehelm-backend',
    version: '2.1.0',
    build: BUILD_HASH,
    trustProxy: app.get('trust proxy'),
    time: new Date().toISOString(),
  });
});

// Routes API
app.use('/api/auth', authRoutes);
app.use('/api/finance', financeRoutes);
app.use('/api/goals', goalRoutes);
app.use('/api/routines', routineRoutes);
app.use('/api/health', healthRoutes);
app.use('/api/accessible', accessibleRoutes);
app.use('/api/ai', aiRoutes);
app.use('/api', userRoutes);
// V2
app.use('/api/family', familyRoutes);
app.use('/api/subscriptions', subscriptionRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/exports', exportRoutes);
app.use('/api/sms-imports', smsImportRoutes);
app.use('/api/sync', syncRoutes);

// Webhook FedaPay (sans auth)
app.use('/api/payments/webhook/fedapay', (req, res, next) => {
  // Le webhook doit être accessible sans JWT, mais on route via subscriptionRoutes
  next();
});

// 404
app.use((_req, res) => {
  res.status(404).json({ error: 'NOT_FOUND' });
});

// Error handler
app.use(errorHandler);

const port = config.port;
const host = '0.0.0.0';

console.log(`▶️  Binding server on ${host}:${port}...`);

const server = app.listen(port, host, () => {
  console.log('═══════════════════════════════════════════════');
  console.log(`🚀 LifeHelm backend LISTENING on ${host}:${port}`);
  console.log(`📋 Environment: ${config.nodeEnv}`);
  console.log(`🌍 CORS: ${config.corsOrigin}`);
  console.log('═══════════════════════════════════════════════');
});

server.on('error', (err: any) => {
  console.error('❌ SERVER ERROR:', err.message);
  if (err.code === 'EADDRINUSE') {
    console.error(`   Port ${port} already in use`);
  }
  process.exit(1);
});

server.on('listening', () => {
  console.log(`✅ Server confirmed listening on port ${port}`);
  // Démarre le keepalive Neon (évite le scale-to-zero)
  startKeepalive();
});

// Catch uncaught errors
process.on('uncaughtException', (err) => {
  console.error('❌ UNCAUGHT EXCEPTION:', err);
  process.exit(1);
});

process.on('unhandledRejection', (reason) => {
  console.error('❌ UNHANDLED REJECTION:', reason);
});

export default app;
