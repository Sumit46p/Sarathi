declare module '*.geojson' {
  import type { GeoJSON } from 'geojson';
  const value: GeoJSON;
  export default value;
}
