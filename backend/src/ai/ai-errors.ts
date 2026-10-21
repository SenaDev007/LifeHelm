import { HttpException, HttpStatus } from '@nestjs/common';

/**
 * Erreurs stables HELM AI (D17.2 §7.6) — codes contractuels consommés par le
 * mobile. Le message est destiné à l'utilisateur final (français), le code à
 * la logique client (retry, re-proposition, blocage).
 */
export const AI_ERRORS = {
  AI_PROVIDER_UNAVAILABLE: {
    status: HttpStatus.SERVICE_UNAVAILABLE,
    message: "L'assistant est momentanément indisponible. Réessayez dans un instant.",
  },
  AI_RATE_LIMITED: {
    status: HttpStatus.TOO_MANY_REQUESTS,
    message: 'Trop de demandes consécutives. Patientez un instant avant de réessayer.',
  },
  AI_CONTEXT_FORBIDDEN: {
    status: HttpStatus.FORBIDDEN,
    message: "Ce périmètre de données n'est pas autorisé pour l'assistant.",
  },
  AI_TOOL_VALIDATION_FAILED: {
    status: HttpStatus.UNPROCESSABLE_ENTITY,
    message: "Les paramètres de l'action ne sont plus valides. Demandez une nouvelle proposition.",
  },
  AI_ACTION_STALE: {
    status: HttpStatus.CONFLICT,
    statusText: 'STALE',
    message: "Les données ont changé depuis la proposition. Une nouvelle proposition est nécessaire.",
  },
  AI_ACTION_EXPIRED: {
    status: HttpStatus.GONE,
    message: 'Délai de confirmation dépassé — la proposition a expiré.',
  },
  AI_ACTION_ALREADY_PROCESSED: {
    status: HttpStatus.CONFLICT,
    message: 'Cette action a déjà été traitée.',
  },
  AI_ACTION_REJECTED: {
    status: HttpStatus.CONFLICT,
    message: 'Cette action a été refusée et ne peut plus être confirmée.',
  },
  AI_OUTPUT_INVALID: {
    status: HttpStatus.SERVICE_UNAVAILABLE,
    message: 'La réponse du modèle était invalide. Reformulez votre demande.',
  },
  AI_CONFIRMATION_REQUIRED: {
    status: HttpStatus.PRECONDITION_REQUIRED,
    message: "Cette opération requiert une confirmation explicite de l'utilisateur.",
  },
  AI_CONSENT_REQUIRED: {
    status: HttpStatus.PRECONDITION_FAILED,
    message: 'Un consentement explicite est requis pour accéder à ce périmètre.',
  },
} as const;

export type AiErrorCode = keyof typeof AI_ERRORS;

export class AiActionError extends HttpException {
  constructor(
    public readonly aiCode: AiErrorCode,
    public readonly detail?: string,
  ) {
    super(
      {
        statusCode: AI_ERRORS[aiCode].status,
        code: aiCode,
        message: AI_ERRORS[aiCode].message,
        ...(detail ? { detail } : {}),
      },
      AI_ERRORS[aiCode].status,
    );
  }
}
