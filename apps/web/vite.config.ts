import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';

// Gear web app: serves the manager hub, the kiosk (installed on an iPad
// home screen), and rider views from one codebase. See docs/08-build-plan.md.
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: { port: 5173 },
});
