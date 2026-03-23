const KEY = "lifehelm_access_token";

export function getAccessToken() {
  if (typeof window === "undefined") return null;
  return sessionStorage.getItem(KEY);
}

export function setAccessToken(token: string) {
  sessionStorage.setItem(KEY, token);
}

export function clearAccessToken() {
  sessionStorage.removeItem(KEY);
}

