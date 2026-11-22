import path from "node:path";
import { lezer } from "@lezer/generator/rollup";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const api = process.env.CACHEPANEL_API_URL ?? "http://localhost:8686";

export default defineConfig({
  plugins: [react(), tailwindcss(), lezer()],
  resolve: { alias: { "@": path.resolve(import.meta.dirname, "src") } },
  build: {
    rolldownOptions: {
      output: {
        codeSplitting: {
          groups: [
            { name: "react", test: /node_modules[\\/](react|react-dom|scheduler)[\\/]/ },
            { name: "tanstack", test: /node_modules[\\/]@tanstack[\\/]/ },
            { name: "radix", test: /node_modules[\\/](radix-ui|@radix-ui)[\\/]/ },
            { name: "codemirror", test: /node_modules[\\/](@codemirror|@lezer)[\\/]/ },
          ],
        },
      },
    },
  },
  server: {
    proxy: {
      "/api": {
        target: api,
        ws: true,
        configure: (proxy) => {
          proxy.on("proxyReqWs", (request) => request.setHeader("origin", api));
        },
      },
    },
  },
});
