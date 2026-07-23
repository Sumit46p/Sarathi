# 🚑 Sarthi — Smart Vehicle Dispatch System

Sarthi is an intelligent, location-aware vehicle dispatch platform built for
emergency and municipal services. It enables real-time tracking and routing of
ambulances, logistics trucks, and municipal vehicles using geospatial data,
helping dispatchers assign the nearest available vehicle to any request. The
backend is powered by Django + PostGIS with OSRM real-road routing, a React
dashboard for dispatchers/admins, and a Flutter mobile app for drivers.

---

## ✅ Current Status

### Core Platform
- [x] Django project scaffolded (`sarthi_backend`)
- [x] PostGIS database running via Docker
- [x] Vehicle model with GPS PointField + admin map picker
- [x] JWT Authentication & Accounts app (`rest_framework_simplejwt`)
- [x] Login accepts **username or email**
- [x] Frontend auth pages (Login & Signup)
- [x] React Router with Protected Routes
- [x] Organization scoping (per-admin/org data isolation)

### Fleet & Dispatch
- [x] Vehicle CRUD (API + dashboard UI)
- [x] Vehicle number plates
- [x] Driver management via `vehicles.Driver` model + `accounts` JWT auth
- [x] **Admin-created driver logins**: admin creates a driver with `username` + `password` (Django `User` linked to the `Driver` profile)
- [x] **Two-way availability sync**: `Driver.is_on_duty` + `Vehicle.admin_blocked` derive `Vehicle.is_available` (driver toggle drives availability; admin block overrides it)
- [x] Nearest-vehicle dispatch (PostGIS distance, OSRM-ranked)
- [x] Dispatch UI (map click → assign → route line)
- [x] **Dispatch lifecycle** (`assigned → accepted → en_route → arrived → completed`, plus `cancelled`) — dispatcher **or** driver can accept (first wins)
- [x] Location simulator (stands in for the Flutter app)
- [x] Live vehicle map (Leaflet, 5s polling)
- [x] **Clickable fleet rows → live vehicle map panel** (see a vehicle's real-time position on demand)
- [x] OSRM real-road routing (route geometry returned to both dashboard and driver app)
- [x] Token refresh flow
....................................
### Driver Mobile App (Flutter) — built
- [x] JWT login (username/email + password)
- [x] **On Duty toggle** → sets `Driver.is_on_duty` (requests location permission, sends immediate GPS fix + 5s polling)
- [x] Driver's assigned vehicle shown from `/api/drivers/me/`
- [x] **Trips tab**: live dispatch route on a map + status transitions (Accept / En Route / Arrived / Complete)
- [x] Profile, Alerts, SOS placeholders

### Implemented (completed in this cycle)
- [x] Maintenance monitoring + scheduled service alerts (CRUD, overdue flagging, dashboard UI)
- [x] Maintenance tab in frontend (vehicle-filtered table, status badges, mark-complete, delete)
- [x] Removed Firebase/`drivers` app — standardized on Django REST + JWT (no separate `drivers` app)
- [x] Active dispatch endpoint (`GET /api/dispatch/active/`) — returns owner's latest active dispatch with live OSRM route geometry
- [x] Dashboard polls active dispatch every 5s and renders the live route as a green polyline on the map
- [x] Fixed vehicle availability bug: `has_active_dispatch` method call in `is_available` derivation

### Not Yet Started / Partial
- [ ] Expense tracking (fuel, maintenance, operational costs)
- [ ] Operational analytics/reporting dashboard (Chart.js/Recharts)
- [ ] Real-time WebSocket notifications (Django Channels) — currently using polling
- [ ] Redis caching layer
- [ ] Role-based access control *within* an organization (one admin = one org; no dispatcher/viewer sub-roles yet)
- [ ] Firebase Cloud Messaging push notifications
- [ ] Docker Compose full-stack deployment (Nginx + Gunicorn)
- [ ] Unit / integration testing
- [ ] User Acceptance Testing (UAT) with a partner organization
- [ ] Performance benchmarking (sub-2s dispatch @ 50 concurrent updates/sec)

> **Architecture Note:** Vehicles and drivers are scoped per-admin/organization. An admin only sees and manages vehicles/drivers belonging to their own organization (Ambulance, Logistics, or Municipal). A `Driver` is linked to a Django `User` (for mobile login) and optionally assigned to a `Vehicle`. Vehicle availability is **derived**: `is_available = driver.is_on_duty AND NOT admin_blocked`.

---

## 📋 Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Python | 3.11+ | Tested with 3.x on Windows |
| Node.js | 18+ | For the React frontend (Vite) |
| Flutter | 3.x | For the driver mobile app (`driver_app/`) |
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

You should see output ending with something like:
```
Applying vehicles.0010_driver_is_on_duty_vehicle_admin_blocked... OK
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

Visit **http://localhost:5173** to see the live vehicle map and dispatch console.

### 10. Run the Flutter driver app

```bash
cd driver_app
flutter pub get
flutter run
```

Log in with a **driver account** created from the dashboard (Admin → Drivers → Add driver, with username + password). The driver's On Duty toggle and Trips tab connect to the same backend.

---

## 🔌 API Endpoints

All endpoints are under the project root (`sarthi_backend/urls.py` → app routers).
Auth: `Authorization: Bearer <access_token>`.

### Auth (`/api/auth/`)
| Method | URL | Description |
|--------|-----|-------------|
| POST | `/api/auth/login/` | Obtain JWT (accepts `username` **or** `email` + `password`) |
| POST | `/api/auth/login/refresh/` | Refresh access token |
| POST | `/api/auth/register/` | Register a new admin/user (username, email, password, organization_type) |
| GET | `/api/auth/me/` | Current user + organization type |

### Vehicles (`/api/`)
| Method | URL | Description |
|--------|-----|-------------|
| GET | `/api/vehicles/` | List vehicles for current org |
| POST | `/api/vehicles/` | Create a vehicle |
| GET | `/api/vehicles/<id>/` | Vehicle detail |
| PATCH | `/api/vehicles/<id>/` | Update (incl. `admin_blocked`) |
| DELETE | `/api/vehicles/<id>/` | Remove a vehicle |
| POST | `/api/vehicles/<id>/update-location/` | Update GPS location `{"lat":..,"lng":..}` |
| POST | `/api/vehicles/<id>/assign-driver/` | Assign a driver `{"driver_id": <id>}` |
| POST | `/api/vehicles/<id>/dispatch/transition/` | **Admin** advances the active dispatch (accept/en_route/arrived/completed/cancelled) |

### Dispatch
| Method | URL | Description |
|--------|-----|-------------|
| POST | `/api/dispatch/` | Dispatch nearest available vehicle `{"lat":..,"lng":..,"vehicle_type":..}` |
| GET | `/api/dispatch/active/` | Owner's latest active dispatch with live route geometry |

### Drivers (`/api/`)
| Method | URL | Description |
|--------|-----|-------------|
| GET | `/api/drivers/` | List drivers for current org |
| POST | `/api/drivers/` | Create a driver **with login credentials** (`name`, `phone_number`, `license_number`, `username`, `password`) |
| GET | `/api/drivers/me/` | Current driver's profile + assigned vehicle + `is_on_duty` |
| PATCH | `/api/drivers/me/duty/` | Set `{"is_on_duty": true|false}` (drives vehicle availability) |
| GET | `/api/drivers/me/dispatch/` | Active dispatch for the driver's vehicle (status + route geometry) |
| POST | `/api/drivers/me/dispatch/transition/` | **Driver** advances the dispatch (accept/en_route/arrived/completed/cancelled) |
| GET | `/api/drivers/<id>/` | Driver detail |
| PATCH | `/api/drivers/<id>/` | Driver update |
| DELETE | `/api/drivers/<id>/` | Remove a driver |

### Maintenance (`/api/`)
| Method | URL | Description |
|--------|-----|-------------|
| GET | `/api/maintenance/` | List maintenance records |
| POST | `/api/maintenance/` | Create a record |
| GET | `/api/maintenance/<id>/` | Detail |
| PATCH | `/api/maintenance/<id>/` | Update (mark completed) |
| DELETE | `/api/maintenance/<id>/` | Remove |
| GET | `/api/maintenance/upcoming/` | Due in next 30 days |

**Location format** — all location endpoints use plain JSON `{"lat": 26.65, "lng": 87.89}`.

**Examples**

Create a vehicle:
```bash
curl -X POST http://localhost:8000/api/vehicles/ \
  -H "Content-Type: application/json" \
  -d '{"name": "Ambulance-01", "vehicle_type": "ambulance", "is_available": true, "location": {"lat": 26.6468, "lng": 87.8942}}'
```

Create a driver **with login credentials** (admin only):
```bash
curl -X POST http://localhost:8000/api/drivers/ \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <admin_token>" \
  -d '{"name": "John Doe", "phone_number": "9876543210", "license_number": "DL-12345", "username": "john", "password": "securepass123"}'
```

Driver login (username **or** email):
```bash
curl -X POST http://localhost:8000/api/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{"username": "john", "password": "securepass123"}'
```

Set driver on duty (this makes the assigned vehicle available):
```bash
curl -X PATCH http://localhost:8000/api/drivers/me/duty/ \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <driver_token>" \
  -d '{"is_on_duty": true}'
```

Driver gets own profile + assigned vehicle:
```bash
curl -X GET http://localhost:8000/api/drivers/me/ \
  -H "Authorization: Bearer <driver_token>"
```

Update vehicle location (from driver app or simulator):
```bash
curl -X POST http://localhost:8000/api/vehicles/1/update-location/ \
  -H "Content-Type: application/json" \
  -d '{"lat": 26.65, "lng": 87.90}'
```

---

## 🚗 Location Simulator

The simulator script performs a **random walk** near Jhapa, Nepal, calling the
`update-location` endpoint every 4 seconds to simulate a vehicle moving in
real time. It exercises the same endpoint the **Flutter driver app** uses.

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
- Or watch the markers move on the **live map** at http://localhost:5173 (click a vehicle row to open its live map panel)
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

### Terminal 3 — Vehicle simulator (or use the Flutter driver app)
```bash
cd Sarathi
.\venv\Scripts\Activate.ps1      # Windows
python scripts/simulate_vehicle.py 1
```

Then open **http://localhost:5173** — you should see the vehicle marker moving
on the map every 4 seconds. Open the **Flutter app** as a 4th terminal to drive
the mobile experience (login as a driver, toggle On Duty, watch the dashboard
update live, accept a dispatch from the Trips tab).

---

## 📱 Flutter Driver App

The driver mobile app (`driver_app/`) is fully implemented and connects to the
same JWT backend.

- **Login**: standard Django JWT (`/api/auth/login/`), username or email.
- **On Duty toggle**: `PATCH /api/drivers/me/duty/` sets `Driver.is_on_duty`.
  On enabling, the app requests location permission, captures an immediate GPS
  fix, and polls every 5s, sending updates via `POST /api/vehicles/<id>/update-location/`.
  Because availability is derived, going on duty makes the assigned vehicle
  "Available" on the dashboard; the admin can still force it unavailable via
  `admin_blocked`.
- **Assigned vehicle**: read from `/api/drivers/me/` (`assigned_vehicle`).
- **Trips tab**: fetches the active dispatch from `/api/drivers/me/dispatch/`
  (which includes the OSRM route geometry), draws it on a map, and lets the
  driver advance the lifecycle (Accept → En Route → Arrived → Complete). The
  dispatcher can also accept from the dashboard — first acceptor wins.
- Driver accounts are created by an admin (Dashboard → Drivers → Add driver
  with username + password); the app has no self-signup.

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | Django 5.2 + Django REST Framework |
| Auth | `djangorestframework-simplejwt` (JWT) |
| Geospatial | GeoDjango + PostGIS + GDAL/GEOS |
| Database | PostgreSQL 16 + PostGIS 3.4 (Docker) |
| API | Django REST Framework |
| Routing | OSRM (real-road distance + geometry) |
| Simulator | Python + requests (random walk) |
| Frontend | React + TypeScript + Vite + Leaflet |
| Mobile | Flutter (driver app) |

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
│   ├── urls.py                     # Root routes
│   ├── wsgi.py
│   └── asgi.py
├── vehicles/                       # Vehicle tracking + dispatch + drivers
│   ├── models.py                   # Vehicle + DispatchRequest + Driver
│   │                              #   (Driver.is_on_duty, Vehicle.admin_blocked)
│   ├── serializers.py             # DRF serializers ({lat, lng}, driver login,
│   │                              #   driver duty/dispatch)
│   ├── views.py                    # CRUD, nearest, dispatch, driver_me,
│   │                              #   driver_duty, driver_dispatch + transition,
│   │                              #   admin dispatch_transition
│   ├── urls.py                    # /api/vehicles/, /api/drivers/, /api/dispatch/
│   ├── osrm.py                    # OSRM real-road routing helper
│   ├── admin.py                   # GIS admin with map picker
│   ├── signals.py                 # Recompute vehicle availability on changes
│   └── migrations/                # 0001_initial … 0010_driver_is_on_duty_*
├── accounts/                       # JWT auth + user profiles
│   ├── models.py                   # Profile (org type)
│   ├── serializers.py              # Register + email/username login
│   ├── views.py                    # LoginView, RegisterView, UserDetailView
│   └── urls.py
├── driver_app/                     # Flutter mobile app (drivers)
│   ├── lib/
│   │   ├── services/api_service.dart
│   │   ├── screens/
│   │   │   ├── login_screen.dart
│   │   │   ├── dashboard_screen.dart   # Home + On Duty toggle + live GPS
│   │   │   ├── trips_screen.dart       # Live dispatch route + transitions
│   │   │   ├── profile_screen.dart
│   │   │   ├── alerts_screen.dart
│   │   │   └── sos_screen.dart
│   │   ├── widgets/
│   │   └── theme.dart
│   ├── pubspec.yaml
│   └── ...
└── frontend/                       # React + TypeScript + Vite (dispatcher console)
    ├── src/
    │   ├── api/auth.ts              # Axios instance with JWT headers
    │   ├── components/
    │   │   ├── FleetMap.tsx         # Live Leaflet map
    │   │   ├── MaintenanceTab.tsx
    │   │   ├── ProtectedRoute.tsx
    │   │   └── ThemeToggle.tsx
    │   ├── pages/
    │   │   ├── Dashboard.tsx        # Fleet + Dispatch + Drivers + live map panel
    │   │   ├── Login.tsx
    │   │   └── Signup.tsx
    │   ├── App.tsx
    │   └── main.tsx
    ├── package.json
    └── vite.config.ts
```

---

## 👥 Team

Built by a team of 4 students. See GitHub contributors for details.
