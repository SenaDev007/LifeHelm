// V2 — Service FedaPay (sandbox)
// Docs: https://fedapay.com/docs/api
// Pour la prod, mettre FEDAPAY_SECRET_KEY dans .env
import { config } from '../config.js';

const FEDAPAY_BASE = process.env.FEDAPAY_BASE_URL || 'https://sandbox-api.fedapay.com/v1';
const FEDAPAY_KEY = process.env.FEDAPAY_SECRET_KEY || '';

interface InitiateParams {
  amount: number;
  currency: string;
  description: string;
  callbackUrl: string;
  paymentMethod?: string;
  phone?: string;
  reference: string;
}

interface InitiateResult {
  id: string;
  reference: string;
  checkoutUrl: string;
}

interface VerifyResult {
  id: string;
  status: string;
  method: string;
  amount: number;
}

// Si pas de clé FedaPay configurée, on simule (mode démo)
const isMockMode = !FEDAPAY_KEY;

export async function initiateFedaPayPayment(params: InitiateParams): Promise<InitiateResult> {
  if (isMockMode) {
    console.log('[FedaPay MOCK] Initiate', params);
    // En mode mock, on simule un paiement déjà approuvé
    return {
      id: `mock_${params.reference}_${Date.now()}`,
      reference: params.reference,
      checkoutUrl: `${config.corsOrigin}/payments/mock-callback?ref=${params.reference}`,
    };
  }

  const res = await fetch(`${FEDAPAY_BASE}/transactions`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${FEDAPAY_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      description: params.description,
      amount: params.amount,
      currency: { iso: params.currency },
      callback_url: params.callbackUrl,
      metadata: { reference: params.reference, method: params.paymentMethod, phone: params.phone },
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`FedaPay initiate failed: ${res.status} ${text}`);
  }

  const data = await res.json() as any;
  const tx = data.data || data;

  return {
    id: String(tx.id),
    reference: tx.reference || params.reference,
    checkoutUrl: tx.checkout_url || `${config.corsOrigin}/payments/callback?ref=${tx.id}`,
  };
}

export async function verifyFedaPayPayment(transactionId: string): Promise<VerifyResult> {
  if (isMockMode) {
    console.log('[FedaPay MOCK] Verify', transactionId);
    // En mode mock, on approuve automatiquement après 5s
    return {
      id: transactionId,
      status: 'approved',
      method: 'MOCK',
      amount: 0,
    };
  }

  const res = await fetch(`${FEDAPAY_BASE}/transactions/${transactionId}`, {
    method: 'GET',
    headers: { 'Authorization': `Bearer ${FEDAPAY_KEY}` },
  });

  if (!res.ok) {
    throw new Error(`FedaPay verify failed: ${res.status}`);
  }

  const data = await res.json() as any;
  const tx = data.data || data;

  return {
    id: String(tx.id),
    status: tx.status,
    method: tx.payment_method?.type || 'unknown',
    amount: tx.amount,
  };
}

export { isMockMode };
