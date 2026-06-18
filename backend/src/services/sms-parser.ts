// V2 — Parser SMS Mobile Money
// Reconnaît les formats MTN, Moov, Wave envoyés en français
// Format typique: "Vous avez recu 5000 FCFA de KOFI MARTIN. Solde: 45000 FCFA. Ref: MP240101.1234.A56789"

interface ParsedSms {
  provider?: string;
  type?: 'INCOME' | 'EXPENSE' | 'TRANSFER';
  amount?: number;
  counterparty?: string;
  reference?: string;
  balance?: number;
  category?: string;
  label?: string;
  date?: Date;
}

export function parseMoMoSms(rawSms: string, sender: string): ParsedSms {
  const text = rawSms.toLowerCase().trim();
  const result: ParsedSms = {};

  // Détection du provider
  if (sender.toLowerCase().includes('mtn') || text.includes('mtn') || text.includes('momo')) {
    result.provider = 'MTN';
  } else if (sender.toLowerCase().includes('moov') || text.includes('moov')) {
    result.provider = 'MOOV';
  } else if (sender.toLowerCase().includes('wave') || text.includes('wave')) {
    result.provider = 'WAVE';
  } else {
    result.provider = 'UNKNOWN';
  }

  // Détection du type d'opération
  if (text.includes('recu') || text.includes('reçu') || text.includes('reception') || text.includes('déposé') || text.includes('depose')) {
    result.type = 'INCOME';
  } else if (text.includes('envoye') || text.includes('envoyé') || text.includes('paie') || text.includes('paye') || text.includes('retire') || text.includes('retiré')) {
    result.type = 'EXPENSE';
  } else if (text.includes('transfert') || text.includes('transfer')) {
    result.type = 'TRANSFER';
  }

  // Extraction du montant (regex pour FCFA ou F)
  const amountMatch = rawSms.match(/(\d[\d\s.,]*)\s*(?:fcfa|f|cfa)/i);
  if (amountMatch) {
    const cleaned = amountMatch[1].replace(/[\s.,]/g, '');
    const amount = parseInt(cleaned, 10);
    if (!isNaN(amount) && amount > 0) {
      result.amount = amount;
    }
  }

  // Extraction du solde
  const balanceMatch = rawSms.match(/(?:solde|balance|nouveau solde)[\s:]*(\d[\d\s.,]*)\s*(?:fcfa|f|cfa)/i);
  if (balanceMatch) {
    const cleaned = balanceMatch[1].replace(/[\s.,]/g, '');
    const balance = parseInt(cleaned, 10);
    if (!isNaN(balance)) {
      result.balance = balance;
    }
  }

  // Extraction de la référence
  const refMatch = rawSms.match(/(?:ref|reference|id)[:\s]*([A-Z0-9][A-Z0-9.\-]{5,30})/i);
  if (refMatch) {
    result.reference = refMatch[1];
  }

  // Extraction du contrepartie (de/à)
  const fromMatch = rawSms.match(/(?:de|from|par)\s+([A-Z][A-Z\s]{2,30})/i);
  const toMatch = rawSms.match(/(?:à|a|to|vers)\s+([A-Z][A-Z\s]{2,30})/i);
  if (fromMatch && result.type === 'INCOME') {
    result.counterparty = fromMatch[1].trim();
  } else if (toMatch && result.type === 'EXPENSE') {
    result.counterparty = toMatch[1].trim();
  }

  // Catégorisation heuristique
  if (result.type === 'EXPENSE') {
    if (text.includes('credit') || text.includes('crédit') || text.includes('data') || text.includes('forfait')) {
      result.category = 'Communication';
    } else if (text.includes('boutique') || text.includes('achat')) {
      result.category = 'Alimentation';
    } else if (text.includes('transport') || text.includes('taxi')) {
      result.category = 'Transport';
    } else if (text.includes('facture') || text.includes('sbee') || text.includes('soneb')) {
      result.category = 'Énergie';
    } else {
      result.category = 'Autre';
    }
  } else if (result.type === 'INCOME') {
    if (text.includes('salaire')) {
      result.category = 'Salaire';
    } else if (text.includes('vente')) {
      result.category = 'Vente';
    } else {
      result.category = 'Autre';
    }
  }

  // Label
  if (result.counterparty && result.type) {
    result.label = result.type === 'INCOME'
      ? `Reçu de ${result.counterparty}`
      : `Envoyé à ${result.counterparty}`;
  } else if (result.provider) {
    result.label = `Transaction ${result.provider}`;
  }

  return result;
}

// Liste des numéros courts connus (pour filtrer les SMS)
export const KNOWN_MOMO_SENDERS = [
  'MTN', 'Moov', 'WAVE', 'OrangeMoney',
  '3031', '3032', '3033', '3034', '3035', // MTN MoMo
  '97000', '97100', // Moov
  'WAVE',
];
