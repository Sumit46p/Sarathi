import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { readFileSync } from 'fs'
import type { Plugin } from 'vite'

/**
 * Vite plugin to load .geojson files as JSON modules.
 * Rolldown / Vite 8 does not natively parse .geojson, so this plugin
 * intercepts .geojson imports and returns parsed JSON.
 */
function geojsonPlugin(): Plugin {
  return {
    name: 'vite-plugin-geojson',
    transform(_code, id) {
      if (id.endsWith('.geojson')) {
        const json = readFileSync(id, 'utf-8')
        // Validate it's real JSON, then export it
        JSON.parse(json)
        return {
          code: `export default ${json}`,
          map: null,
        }
      }
    },
  }
}

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), geojsonPlugin()],
})
