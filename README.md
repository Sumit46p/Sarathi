# 🚑 Sarthi — Smart Vehicle Dispatch System

Sarthi is an intelligent, location-aware vehicle dispatch platform built for
emergency and municipal services. It enables real-time tracking and routing of
ambulances, logistics trucks, and municipal vehicles using geospatial data,
helping dispatchers assign the nearest available vehicle to any request. The
backend is powered by Django + PostGIS, with planned integrations for OSRM
routing, a React dashboard, and a Flutter mobile app.

---

## ✅ Current Status

- [x] Django project scaffolded (`sarthi_backend`)
- [x] PostGIS database running via Docker (port **5433**)
- [x] `Vehicle` model with GPS `PointField` + admin map picker
- [x] Database migrations applied
- [x] REST API endpoints (DRF) — CRUD + location update
- [x] JWT Authentication & Accounts app setup
- [x] Frontend Authentication pages (Login & Signup UI)
- [x] React Router with Protected Routes for dashboard
- [x] Location simulator script (stands in for Flutter driver app)
- [x] React frontend — live vehicle map with Leaflet
- [x] Cross-platform GDAL/GEOS paths handled (Windows OSGeo4W support)
- [x] Vehicle CRUD UI (add modal, toggle availability, delete)
- [x] Nearest-vehicle dispatch endpoint (PostGIS distance)
- [x] Dispatch UI (map click → assign nearest vehicle → route line)
- [x] Organization scoping (vehicles isolated per-admin based on org type)
- [x] Driver management (add drivers, assign to vehicles)
- [x] Vehicle number plates
- [ ] OSRM real-road routing integration
- [ ] Flutter mobile app

> **Architecture Note:** Vehicles are scoped per-admin/organization. An admin only sees and manages vehicles belonging to their own organization (Ambulance, Logistics, or Municipal). This was a deliberate architecture correction after initial testing revealed cross-org data mixing.

---

## 📋 Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Python | 3.11+ | Tested with 3.x on Windows |
| Node.js | 18+ | For the React frontend (Vite) |
| Docker | Latest | For PostGIS container |
| GDAL/GEOS | via OSGeo4W | Required for GeoDjango spatial fields |
| Git | Latest | For version control |

---

## 🚀 Setup Instructions

Follow these steps **exactly** to get the project running on your machine.

### 1. Clone the repo

```bash
git clone https://github.com/Sumit46p/Sarathi.git
cd Sarathi
```

### 2. Start the PostGIS database (Docker)

```bash
docker run -d --name sarthi-db \
  -e POSTGRES_PASSWORD=devpass \
  -p 5433:5432 \
  postgis/postgis:16-3.4
```

> **Note:** We use port **5433** on the host to avoid conflicts with any locally
> installed PostgreSQL. The container internally uses 5432.

Wait ~10 seconds for the database to initialize before proceeding.

### 3. Install GDAL / GEOS system libraries

GDAL and GEOS are **C libraries** required by GeoDjango for spatial operations.

#### Windows (OSGeo4W)
1. Download the installer: https://download.osgeo.org/osgeo4w/v2/osgeo4w-setup.exe
2. Run it → **Express Install** → check **GDAL**
3. Default install path: `C:\Users\<you>\AppData\Local\Programs\OSGeo4W`
4. Update `OSGEO4W` path in `sarthi_backend/settings.py` if your install path differs
5. Also verify the GDAL DLL filename matches (e.g., `gdal313.dll`) — check your
   `OSGeo4W\bin\` folder and update `GDAL_LIBRARY_PATH` in settings if needed

#### macOS (Homebrew)
```bash
brew install gdal geos
```

#### Ubuntu / Debian
```bash
sudo apt-get install gdal-bin libgdal-dev libgeos-dev
```

### 4. Create and activate virtual environment

```bash
python -m venv venv

# Windows (PowerShell)
.\venv\Scripts\Activate.ps1

# macOS / Linux
source venv/bin/activate
```

### 5. Install Python dependencies

```bash
pip install -r requirements.txt
```

### 6. Run database migrations

```bash
python manage.py migrate
```

You should see output ending with:
```
Applying vehicles.0001_initial... OK
```

### 7. Create a superuser

```bash
python manage.py createsuperuser
```

Enter a username, email, and password when prompted.

### 8. Run the development server

```bash
python manage.py runserver
```

Visit:
- **http://localhost:8000/admin/** — Django admin (log in with your superuser)
- **http://localhost:8000/api/vehicles/** — Browsable API (DRF)
- Add test vehicles using the **map picker** in admin, or via the API

### 9. Set up the React frontend

```bash
cd frontend
npm install
npm run dev
```

Visit **http://localhost:5173** to see the live vehicle map.

---

## 🔌 API Endpoints

| Method | URL | Description |
|--------|-----|-------------|
| GET | `/api/auth/me/` | Get current user and organization type |
| GET | `/api/vehicles/` | List all vehicles for current org |
| POST | `/api/vehicles/` | Create a new vehicle for current org |
| GET | `/api/vehicles/<id>/` | Detail of one vehicle |
| PATCH | `/api/vehicles/<id>/` | Partial update (toggle availability, edit) |
| DELETE | `/api/vehicles/<id>/` | Remove a vehicle |
| POST | `/api/vehicles/<id>/update-location/` | Update GPS location |
| GET | `/api/vehicles/nearest/?lat=..&lng=..&type=..` | Top 5 nearest available vehicles in org |
| POST | `/api/dispatch/` | Dispatch nearest vehicle in org |

**Location format** — all endpoints use plain JSON `{"lat": 26.65, "lng": 87.89}` (not GeoJSON/WKT).

**Example — create a vehicle:**
```bash
curl -X POST http://localhost:8000/api/vehicles/ \
  -H "Content-Type: application/json" \
  -d '{"name": "Ambulance-01", "vehicle_type": "ambulance", "is_available": true, "location": {"lat": 26.6468, "lng": 87.8942}}'
```

**Example — update location:**
```bash
curl -X POST http://localhost:8000/api/vehicles/1/update-location/ \
  -H "Content-Type: application/json" \
  -d '{"lat": 26.65, "lng": 87.90}'
```

---

## 🚗 Location Simulator

The simulator script performs a **random walk** near Jhapa, Nepal, calling the
`update-location` endpoint every 4 seconds to simulate a vehicle moving in
real time. This stands in for the real **Flutter driver app**, which will call
the same endpoint later.

### Running the simulator

```bash
# First, create a test vehicle (if you haven't already)
curl -X POST http://localhost:8000/api/vehicles/ \
  -H "Content-Type: application/json" \
  -d '{"name": "Test-Vehicle", "vehicle_type": "ambulance", "is_available": true, "location": {"lat": 26.6468, "lng": 87.8942}}'

# Note the "id" in the response (e.g., 1), then run:
python scripts/simulate_vehicle.py 1

# Optional: faster updates (every 2 seconds)
python scripts/simulate_vehicle.py 1 --interval 2
```

While the simulator runs, verify the location is changing:
- Visit **http://localhost:8000/api/vehicles/1/** and refresh
- Or watch the markers move on the **live map** at http://localhost:5173
- Or check Django admin → Vehicles → click the vehicle → see the map marker move

---

## 🗺️ Running the Full Stack

To see everything working together, you need **3 terminals** running simultaneously:

### Terminal 1 — Django API server
```bash
cd Sarathi
.\venv\Scripts\Activate.ps1      # Windows
python manage.py runserver
```

### Terminal 2 — React frontend (Vite dev server)
```bash
cd Sarathi/frontend
npm run dev
```

### Terminal 3 — Vehicle simulator
```bash
cd Sarathi
.\venv\Scripts\Activate.ps1      # Windows
python scripts/simulate_vehicle.py 1
```

> **First time?** Before running the simulator, create a test vehicle:
> ```bash
> curl -X POST http://localhost:8000/api/vehicles/ \
>   -H "Content-Type: application/json" \
>   -d '{"name": "Ambulance-01", "vehicle_type": "ambulance", "is_available": true, "location": {"lat": 26.6468, "lng": 87.8942}}'
> ```

Then open **http://localhost:5173** — you should see the vehicle marker moving
on the map every 4 seconds.

---

## 📱 Planned Flutter App Scope (Next Phase)

The mobile application for drivers is the primary focus for the next development phase. Key planned features include:
- **Authentication**: Driver login linked to their assigned organization.
- **Duty Toggle**: Simple on/off duty switch indicating availability for dispatch.
- **Live Location**: Background GPS tracking synced with the Django backend.
- **Current Assignment**: Clear view of their current vehicle assignment and details.
- **Dispatch Notifications**: Real-time alerts when assigned to a new emergency or dispatch request, with navigation integration.

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | Django 5.2 + Django REST Framework |
| Geospatial | GeoDjango + PostGIS + GDAL/GEOS |
| Database | PostgreSQL 16 + PostGIS 3.4 (Docker) |
| API | Django REST Framework |
| Simulator | Python + requests (random walk) |
| Frontend | React + TypeScript + Vite + Leaflet |
| Routing | OSRM (planned) |
| Mobile | Flutter (planned) |

---

## 📁 Project Structure

```
Sarathi/
├── manage.py
├── requirements.txt
├── scripts/
│   └── simulate_vehicle.py        # Location simulator (random walk)
├── sarthi_backend/                 # Django project config
│   ├── settings.py                 # DB, GDAL, CORS, installed apps
│   ├── urls.py                     # Routes /api/ to vehicles.urls
│   ├── wsgi.py
│   └── asgi.py
├── vehicles/                       # Vehicle tracking + dispatch app
│   ├── models.py                   # Vehicle + DispatchRequest models
│   ├── serializers.py              # DRF serializers ({lat, lng} format)
│   ├── views.py                    # API views (CRUD, nearest, dispatch)
│   ├── urls.py                     # /api/vehicles/ + /api/dispatch/
│   ├── admin.py                    # GIS admin with map picker
│   └── migrations/
│       ├── 0001_initial.py
│       └── 0002_add_dispatch_request.py
└── frontend/                       # React + TypeScript + Vite
    ├── src/
    │   ├── api/auth.ts              # Axios instance with JWT headers
    │   ├── components/
    │   │   ├── FleetMap.tsx         # Live Leaflet map
    │   │   ├── ProtectedRoute.tsx   # Auth route wrapper
    │   │   └── ThemeToggle.tsx      # UI theme switcher
    │   ├── pages/
    │   │   ├── Dashboard.tsx        # Fleet overview + Dispatch + Settings
    │   │   ├── Login.tsx            # User login page
    │   │   └── Signup.tsx           # User registration
    │   ├── App.tsx
    │   └── main.tsx
    ├── package.json
    └── vite.config.ts
```

---

## 👥 Team

Built by a team of 4 students. See GitHub contributors for details.
