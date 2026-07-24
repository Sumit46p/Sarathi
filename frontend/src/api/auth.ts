import axios, { type AxiosError, type InternalAxiosRequestConfig } from 'axios';

const API_URL = 'http://localhost:8000/api';

export const api = axios.create({
  baseURL: API_URL,
});

// Query-string key set on /login when the user was forced out by an expired
// session, so the Login page can surface a clear "session expired" message
// instead of a silent, broken redirect.
export const SESSION_EXPIRED_FLAG = 'session_expired';

declare module 'axios' {
  // eslint-disable-next-line @typescript-eslint/no-empty-object-type
  export interface InternalAxiosRequestConfig {
    _retry?: boolean;
    _skipAuthRefresh?: boolean;
  }
}

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('accessToken');
  if (token && config.headers) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// ── Silent token refresh ───────────────────────────────────────────────────
// When a request fails with 401, we attempt exactly one refresh of the access
// token. If many requests fail simultaneously they all await the same
// in-flight refresh promise (single-flight) so we never hit the refresh
// endpoint more than once per expiry window. On failure we clear tokens and
// send the user to login with a "session expired" notice.
let refreshPromise: Promise<string> | null = null;

function refreshAccessToken(): Promise<string> {
  if (refreshPromise) return refreshPromise;
  refreshPromise = (async () => {
    const refreshToken = localStorage.getItem('refreshToken');
    if (!refreshToken) throw new Error('No refresh token');
    const response = await axios.post(`${API_URL}/auth/login/refresh/`, { refresh: refreshToken });
    const { access } = response.data;
    if (!access) throw new Error('No access token in refresh response');
    localStorage.setItem('accessToken', access);
    return access;
  })().finally(() => {
    refreshPromise = null;
  });
  return refreshPromise;
}

function forceLogout(): void {
  localStorage.removeItem('accessToken');
  localStorage.removeItem('refreshToken');
  const current = new URL(window.location.href);
  if (!current.searchParams.has(SESSION_EXPIRED_FLAG) && !current.pathname.startsWith('/login')) {
    current.searchParams.set(SESSION_EXPIRED_FLAG, '1');
    current.pathname = '/login';
    window.location.replace(current.toString());
  }
}

api.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const originalRequest = error.config as InternalAxiosRequestConfig | undefined;
    const status = error.response?.status;

    // Only attempt a refresh on a genuine 401, once per request, and never for
    // the refresh flow itself (which would recurse forever).
    if (
      status === 401 &&
      originalRequest &&
      !originalRequest._retry &&
      !originalRequest._skipAuthRefresh
    ) {
      originalRequest._retry = true;
      try {
        const access = await refreshAccessToken();
        originalRequest.headers = originalRequest.headers ?? {};
        originalRequest.headers.Authorization = `Bearer ${access}`;
        return api(originalRequest);
      } catch {
        forceLogout();
        return Promise.reject(error);
      }
    }

    // If we already tried to refresh and still got 401, force logout.
    if (status === 401 && originalRequest?._retry) {
      forceLogout();
    }

    return Promise.reject(error);
  }
);

// Backward-compatible alias used by Login and Signup pages.
export const authApi = api;
