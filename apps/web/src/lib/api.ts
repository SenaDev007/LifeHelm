import { getAccessToken } from "./session";

export const apiBaseUrl = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

export async function apiFetch<T>(path: string, options?: RequestInit & { auth?: boolean }) {
  const url = `${apiBaseUrl}${path}`;
  const authToken = options?.auth ? getAccessToken() : null;
  const res = await fetch(url, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(options?.headers ?? {}),
      ...(authToken ? { Authorization: `Bearer ${authToken}` } : {}),
    },
    // Les cookies httpOnly (refresh token) seront envoyés côté browser
    credentials: "include",
  });

  const bodyText = await res.text();
  const body = bodyText ? JSON.parse(bodyText) : null;

  if (!res.ok) {
    const message = body?.error?.message ?? body?.message ?? res.statusText;
    throw new Error(message);
  }

  return body as T;
}

