import { MapContainer, TileLayer, GeoJSON } from 'react-leaflet';
import type { MapContainerProps } from 'react-leaflet';
import NEPAL_GEOJSON from '../data/nepalBorder';
import { NEPAL_CENTER, MAP_OPTIONS, NEPAL_BORDER_STYLE } from '../utils/constants';

interface BaseMapProps extends MapContainerProps {
  children?: React.ReactNode;
}

export default function BaseMap({ children, ...props }: BaseMapProps) {
  return (
    <MapContainer
      center={NEPAL_CENTER}
      zoom={MAP_OPTIONS.minZoom}
      minZoom={MAP_OPTIONS.minZoom}
      maxBounds={MAP_OPTIONS.maxBounds}
      maxBoundsViscosity={MAP_OPTIONS.maxBoundsViscosity}
      style={{ width: '100%', height: '100%' }}
      {...props}
    >
      <TileLayer
        attribution='&copy; <a href="https://www.esri.com/en-us/home">Esri</a> &mdash; Source: Esri, i-cubed, USDA, USGS, AEX, GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, and the GIS User Community'
        url="https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
      />
      <GeoJSON data={NEPAL_GEOJSON as GeoJSON.GeoJsonObject} style={() => NEPAL_BORDER_STYLE} />
      {children}
    </MapContainer>
  );
}
