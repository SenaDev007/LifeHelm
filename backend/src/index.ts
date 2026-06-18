// Point d'entrée — charge dotenv en TOUT PREMIER avec override
import dotenv from 'dotenv';
import path from 'node:path';
dotenv.config({ path: path.resolve(process.cwd(), '.env'), override: true });

// Puis le reste
import './server.js';
