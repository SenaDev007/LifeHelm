import { Injectable, Logger } from '@nestjs/common';

/**
 * Passerelle modèle — API NVIDIA (compatible OpenAI), Dossier 17 §6.1.
 * - La clé NVIDIA_API_KEY vit UNIQUEMENT côté serveur (jamais dans le mobile).
 * - Aucun accès direct à PostgreSQL : l'orchestrateur fournit un contexte
 *   déjà filtré et minimisé (D17 : « outils métier contrôlés »).
 * - Indisponibilité explicite : sans clé ou en échec, l'API renvoie
 *   TEMPORARY_UNAVAILABLE — jamais de fausse réponse (D17.3 §17.4).
 */
@Injectable()
export class NvidiaProvider {
  private readonly logger = new Logger(NvidiaProvider.name);

  private readonly baseUrl = process.env.NVIDIA_BASE_URL ?? 'https://integrate.api.nvidia.com/v1';
  private readonly apiKey = process.env.NVIDIA_API_KEY ?? '';
  private readonly model = process.env.NVIDIA_AI_MODEL ?? 'openai/gpt-oss-20b';
  private readonly fallbackModel = process.env.NVIDIA_AI_MODEL_FALLBACK ?? 'z-ai/glm-5.3-flash';

  get configured(): boolean {
    return this.apiKey.length > 0;
  }

  get modelKey(): string {
    return this.model;
  }

  /**
   * Appel chat/completions. Renvoie le contenu texte du message.
   * Échec → exception avec code stable consommable par le contrôleur.
   */
  async chat(messages: Array<{ role: string; content: string }>, opts?: {
    temperature?: number;
    maxTokens?: number;
    timeoutMs?: number;
  }): Promise<{ content: string; model: string }> {
    if (!this.configured) {
      throw new NvidiaProviderError('AI_PROVIDER_UNAVAILABLE', 'Fournisseur IA non configuré (NVIDIA_API_KEY absente).');
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), opts?.timeoutMs ?? 45_000);
    try {
      const res = await fetch(`${this.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.apiKey}`,
          Accept: 'application/json',
        },
        body: JSON.stringify({
          model: this.model,
          messages,
          temperature: opts?.temperature ?? 0.4,
          top_p: 1,
          max_tokens: opts?.maxTokens ?? 1200,
          stream: false,
        }),
        signal: controller.signal,
      });

      if (!res.ok) {
        const text = await res.text().catch(() => '');
        // Journalisation minimisée : jamais le contenu des messages.
        this.logger.warn(`NVIDIA HTTP ${res.status} — ${text.slice(0, 180)}`);
        if (res.status === 401 || res.status === 403) {
          throw new NvidiaProviderError('AI_PROVIDER_UNAVAILABLE', 'Clé IA refusée par le fournisseur.');
        }
        if (res.status === 429) {
          throw new NvidiaProviderError('AI_RATE_LIMITED', 'Limite d\'utilisation IA atteinte. Réessayez dans un instant.');
        }
        // Tentative de repli sur le modèle secondaire (une seule fois).
        if (this.fallbackModel && this.fallbackModel !== this.model) {
          return await this.chatWithModel(this.fallbackModel, messages, opts);
        }
        throw new NvidiaProviderError('AI_PROVIDER_UNAVAILABLE', 'Fournisseur IA indisponible.');
      }

      const json = (await res.json()) as {
        choices?: Array<{ message?: { content?: string } }>;
      };
      const content = json.choices?.[0]?.message?.content?.trim();
      if (!content) {
        throw new NvidiaProviderError('AI_OUTPUT_INVALID', 'Réponse du modèle vide ou non conforme.');
      }
      return { content, model: this.model };
    } catch (e) {
      if (e instanceof NvidiaProviderError) throw e;
      if ((e as Error)?.name === 'AbortError') {
        throw new NvidiaProviderError('AI_PROVIDER_UNAVAILABLE', 'Délai dépassé côté fournisseur IA.');
      }
      this.logger.warn(`NVIDIA réseau: ${(e as Error).message}`);
      throw new NvidiaProviderError('AI_PROVIDER_UNAVAILABLE', 'Fournisseur IA injoignable.');
    } finally {
      clearTimeout(timer);
    }
  }

  private async chatWithModel(
    model: string,
    messages: Array<{ role: string; content: string }>,
    opts?: { temperature?: number; maxTokens?: number; timeoutMs?: number },
  ): Promise<{ content: string; model: string }> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), opts?.timeoutMs ?? 45_000);
    try {
      const res = await fetch(`${this.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.apiKey}`,
          Accept: 'application/json',
        },
        body: JSON.stringify({
          model,
          messages,
          temperature: opts?.temperature ?? 0.4,
          top_p: 1,
          max_tokens: opts?.maxTokens ?? 1200,
          stream: false,
        }),
        signal: controller.signal,
      });
      if (!res.ok) {
        throw new NvidiaProviderError('AI_PROVIDER_UNAVAILABLE', 'Fournisseur IA indisponible.');
      }
      const json = (await res.json()) as {
        choices?: Array<{ message?: { content?: string } }>;
      };
      const content = json.choices?.[0]?.message?.content?.trim();
      if (!content) {
        throw new NvidiaProviderError('AI_OUTPUT_INVALID', 'Réponse du modèle vide ou non conforme.');
      }
      return { content, model };
    } finally {
      clearTimeout(timer);
    }
  }
}

export class NvidiaProviderError extends Error {
  constructor(public readonly code: string, message: string) {
    super(message);
  }
}
