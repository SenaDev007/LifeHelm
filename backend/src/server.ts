import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import rateLimit from 'express-rate-limit';
import { config } from './config.js';
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

// Health check
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'lifehelm-backend', version: '1.0.0', time: new Date().toISOString() });
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
app.listen(port, host, () => {
  console.log(`🚀 LifeHelm backend running on http://${host}:${port}`);
  console.log(`📋 Environment: ${config.nodeEnv}`);
  console.log(`🌍 CORS: ${config.corsOrigin}`);
});

export default app;
