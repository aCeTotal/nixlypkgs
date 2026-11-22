export class ApiError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

type Method = "GET" | "POST" | "PUT" | "DELETE";

type RequestOptions = {
  method?: Method;
  body?: unknown;
  signal?: AbortSignal;
};

const offline = new ApiError(0, "offline", "Får ikke kontakt med panelet");

let csrfToken = "";

export function setCsrfToken(token: string) {
  csrfToken = token;
}

async function request(path: string, { method = "GET", body, signal }: RequestOptions) {
  const headers: Record<string, string> = { "X-Cachepanel-CSRF": csrfToken };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  const response = await fetch(`/api${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal,
  }).catch((error: unknown) => {
    if (error instanceof DOMException && error.name === "AbortError") throw error;
    throw offline;
  });
  if (response.ok) return response;
  const payload = (await response.json().catch(() => null)) as { error?: { code: string; message: string } } | null;
  throw new ApiError(response.status, payload?.error?.code ?? "http_error", payload?.error?.message ?? response.statusText);
}

export async function api<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const response = await request(path, options);
  if (response.status === 204) return undefined as T;
  return (await response.json()) as T;
}

// Multipart upload with progress.
export function upload<T>(path: string, file: File, onProgress: (fraction: number) => void): Promise<T> {
  const form = new FormData();
  form.append("file", file);
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("POST", `/api${path}`);
    xhr.setRequestHeader("X-Cachepanel-CSRF", csrfToken);
    xhr.responseType = "json";
    xhr.upload.addEventListener("progress", (event) => event.lengthComputable && onProgress(event.loaded / event.total));
    xhr.addEventListener("error", () => reject(offline));
    xhr.addEventListener("load", () => {
      const payload = xhr.response as (T & { error?: { code: string; message: string } }) | null;
      if (xhr.status >= 200 && xhr.status < 300) return resolve(payload as T);
      reject(new ApiError(xhr.status, payload?.error?.code ?? "http_error", payload?.error?.message ?? xhr.statusText));
    });
    xhr.send(form);
  });
}
