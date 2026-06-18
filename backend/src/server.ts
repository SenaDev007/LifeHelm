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

// 404
app.use((_req, res) => {
  res.status(404).json({ error: 'NOT_FOUND' });
});

// Error handler
app.use(errorHandler);

const port = config.port;
app.listen(port, () => {
  console.log(`🚀 LifeHelm backend running on http://localhost:${port}`);
  console.log(`📋 Environment: ${config.nodeEnv}`);
  console.log(`🌍 CORS: ${config.corsOrigin}`);
});

export default app;
