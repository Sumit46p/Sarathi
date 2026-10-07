# 🚛 Sarathi — Intelligent Fleet Management & Dispatch Platform

> **Enterprise-grade, location-aware fleet intelligence** for emergency response, municipal services, logistics, public transit, and commercial rentals.

Sarathi is a full-stack mono-repo combining:
- 🐍 **Django + PostGIS** backend with OSRM real-road routing
- ⚡ **Redis** for caching, session storage, and WebSocket messaging
- ⚛️ **React 19 + TypeScript + Vite** dispatcher workspace
- 📱 **Flutter** cross-platform driver mobile app

---

## 📐 Architecture Overview

```
sarathi/
├── sarthi_backend/          # Django project settings & ASGI config
├── vehicles/                # Core fleet models, dispatch engine, rules engine
├── accounts/                # JWT auth, organization, driver profiles
├── frontend/                # React + TypeScript + Vite dispatcher dashboard
│   └── src/
│       ├── components/      # Dashboard tabs, maps, dispatch workspace
│       └── hooks/           # WebSocket, polling, auth hooks
├── driver_app/              # Flutter driver mobile app
│   └── lib/
│       ├── screens/         # All app screens (dashboard, trips, fuel, etc.)
│       ├── widgets/         # Reusable widgets (truck loader animation, etc.)
│       ├── services/        # API service layer
│       └── theme.dart       # Design system / color tokens
├── requirements.txt         # Python dependencies
└── manage.py
```

---

## 🏢 Setting Up a New Organization (Multi-Tenancy)
Sarathi is built as a multi-tenant SaaS. To set up a completely isolated new organization:

1. **Register the Admin:** Go to the frontend register page (`http://localhost:5173/register`) and create a new account (e.g., `school_admin`), typing the new organization's name (e.g., `school`) in the Organization Name field. 
   *(Note: For security, the system defaults all new signups to the read-only `VIEWER` role).*
2. **Elevate the Role:** Log in to the Django Admin panel (`http://localhost:8000/admin`) using a superuser account (e.g., `admin`). Go to **Accounts > Profiles**, find the new `school_admin`, and change their Role from `Viewer` to `Organization Admin`.
3. **Isolated Workspace:** When `school_admin` logs into the React frontend, they will see an entirely blank workspace. Any vehicles, drivers, or dispatch operations they create will be exclusively visible to members of the `school` organization.

---

## ✅ Feature Checklist

### 🔐 Authentication & Multi-Tenancy
- [x] JWT authentication (`djangorestframework-simplejwt`)
- [x] Login accepts **username or email**
- [x] Organization scoping — each admin sees only their own fleet/drivers
- [x] Role-based profiles: `ORGANIZATION_ADMIN`, `FLEET_MANAGER`, `DRIVER`, `VIEWER`, `AUDITOR`
- [x] **RBAC enforcement** — `accounts/permissions.py` gates all API write operations by role:
  - Fleet CRUD → Admin only
  - Dispatch create/accept → Dispatcher (FLEET_MANAGER) or Admin
  - GPS submission / duty toggle → Driver only
  - All GET endpoints → Viewer or higher
- [x] Auth rate limiting: login (30/min), register (10/hr), password reset (5/hr)
- [x] Case-insensitive organization name matching
- [x] Driver and Admin organization profile validation enforced on login and registration
- [x] First-login forced password change flow (`requires_password_change` flag)
- [x] JWT session jitter (±5 min) to prevent thundering-herd on mass token expiry

### 🚗 Fleet & Vehicle Management
- [x] Vehicle CRUD (REST API + dashboard UI)
- [x] Vehicle number plates, fuel types (Petrol / Diesel / EV)
- [x] Extended categories: Rental, Government, Company, Personal, Logistics, Public Transport, Commercial
- [x] Custom vehicle photo upload (rendered on map markers and cards)
- [x] **Derived availability**: `is_available = driver.is_on_duty AND NOT admin_blocked`
- [x] Two-way availability sync — driver toggle drives availability; admin block overrides
- [x] Vehicle telemetry overlay: speed, heading, battery/fuel level

### 👨‍✈️ Driver Management
- [x] Admin-created driver logins (Django `User` linked to `Driver` profile)
- [x] Driver assigned to a vehicle; driver on-duty toggle drives vehicle availability
- [x] Driver safety score: `GET /api/drivers/<id>/score/` — 0–100 based on harsh driving events (last 30 days)
- [x] Harsh driving event detection: server-side heuristic (`harsh_accel` / `harsh_brake` / `harsh_turn`)

### 📍 Dispatch & Routing
- [x] **Universal Dispatch Engine** (`vehicles/dispatch_engine.py`) — multi-factor candidate ranking: driver status, road travel time, distance, vehicle suitability, battery/fuel level, emergency priority
- [x] Nearest-vehicle dispatch with PostGIS distance + OSRM-ranked travel time
- [x] **Interactive Dispatch Workspace** — auto-recommendation, one-click manual/automated assignment, live candidate list
- [x] Full dispatch lifecycle: `assigned → accepted → en_route → arrived → completed` (+ `cancelled`)
- [x] Dispatcher **and** driver can accept (first-wins race)
- [x] **Optimized OSRM Routing** — multi-waypoint routes (Vehicle → Pickup → Destination) with `continue_straight` to avoid unnecessary detours.
- [x] **Douglas-Peucker route simplification** — reduces GPS zigzag noise for smooth map drawing.
- [x] Live ETA + route progress (`progress_percent`, `remaining_distance_km`, `eta_min`)
- [x] Dispatch CSV export: `GET /api/dispatch/export/`

### 🗺️ Real-Time Tracking
- [x] GPS breadcrumb recording (`LocationRecord` model)
- [x] Live vehicle map (Leaflet, 5s polling) with active multi-waypoint route overlays
- [x] **Live Fleet Telemetry tab** — full-screen map with status filter pills (all, on duty, en route, idle, offline)
- [x] Clickable fleet rows → live vehicle map panel
- [x] **Rules & Alerts Engine** (`vehicles/rules_engine.py`) — geofencing, speed limits, max idling, service boundaries

### 📜 Trip History & Route Playback
- [x] Trip history API: `GET /api/trips/`
- [x] Route playback API: `GET /api/trips/<id>/playback/` — time-ordered GPS breadcrumbs
- [x] Frontend Trip History tab — animated route playback with play/pause, speed control, scrubber
- [x] Flutter trip history screen — high-contrast cards with status pills and pull-to-refresh

### ⛽ Fuel Management & Expense Tracking
- [x] **New `FuelLog` model** — tracks liters/kWh, amount, odometer, notes, and **receipt image uploads** for petrol/diesel/EV.
- [x] Driver fuel log endpoints: `POST /api/drivers/me/fuel-logs/`, `GET /api/fuel-logs/`
- [x] NOC (Nepal Oil Corporation) fuel price integration — daily scrape + 24hr cache
- [x] Fuel price API: `GET /api/fuel-prices/`
- [x] **Analytics Dashboard Integration** — fuel cost trends and total fuel cost KPIs query the new `FuelLog` tables.
- [x] Receipt preview modal (click thumbnail → full-size)
- [x] Fuel history list in Flutter driver app (pull-to-refresh, status cards)

### 🔧 Maintenance
- [x] `MaintenanceRecord` model with `proof_image`, `completed_by` (Driver FK), `completion_notes`
- [x] Driver maintenance endpoints: `GET /api/drivers/me/maintenance/`, `POST /api/drivers/me/maintenance/<id>/complete/`
- [x] Maintenance CRUD in admin dashboard — overdue flagging, status badges, mark-complete
- [x] Automatic recurrence — `_auto_create_next_record()` creates the next recurring record on completion (time-based and km-based)
- [x] Maintenance history list in Flutter driver app (green FAB, high-contrast cards)

### 🆘 Emergency SOS
- [x] `EmergencyRequest` model with location, description, photo
- [x] Driver endpoint: `POST /api/emergency/requests/create/`
- [x] Admin endpoint: `GET /api/emergency/requests/` (org-scoped), drivers see their own
- [x] Emergency history list in Flutter driver app (red accent, FAB, pull-to-refresh)
- [x] Admin dashboard emergency tab with status workflow

### 🐛 Issue Reporting
- [x] `IssueReport` model with status workflow: `open → acknowledged → resolved`
- [x] Driver endpoint: `POST /api/drivers/me/report-issue/` (multipart, optional photo)
- [x] Admin endpoints: `GET /api/issues/`, `PATCH /api/issues/<id>/`
- [x] Frontend Issues tab — photo thumbnails, status badges, Acknowledge/Resolve actions
- [x] Fleet table warning indicator on vehicles with open issues
- [x] Issue history list in Flutter driver app (high-contrast cards, FAB)

### 📊 Analytics & Reporting
- [x] Analytics dashboard — `km_per_liter` per vehicle, per-driver trip totals
- [x] Driver performance metrics: acceptance rate, completion counts, safety score
- [x] Expense PDF report: `GET /api/expenses/report/pdf/` (fuel + maintenance, per-vehicle)

### 🔔 Real-Time WebSocket Notifications
- [x] **Redis channel layer** (Django Channels) — `ProtocolTypeRouter` + JWT-authenticated `NotificationConsumer`
- [x] Channel groups: `user_notifications_<id>` (personal) + `org_notifications_<org>` (org-wide)
- [x] `post_save` signals on `IssueReport`, `EmergencyRequest`, `MaintenanceRecord`, `Notification` → instant push
- [x] Frontend `useAdminNotifications.ts` hook — auto-reconnects on disconnect
- [x] Smart polling fallback — skips issues/emergencies/maintenance while WebSocket is healthy
- [x] Instant targeted refetch — only affected data type refreshed per event
- [x] `NotificationBell` with live `markAsRead` + `deleteNotification`

### 🛣️ Fixed Routes & Rentals
- [x] Fixed Routes tab — sequenced waypoints/stops, vehicle assignment, schedule tracking
- [x] Commercial Rental tab — customer details, rental start/end dates, rates, active vehicle assignment

### 📱 Flutter Driver App — Full Feature List
- [x] JWT login (username/email + password + organization name)
- [x] On-Duty toggle → sets `Driver.is_on_duty`, requests location permission, sends GPS at 5s interval
- [x] Assigned vehicle shown from `/api/drivers/me/`
- [x] **Dashboard** — status overview, weather-style cards
- [x] **Trips tab** — live dispatch route on Leaflet map, status transitions (Accept / En Route / Arrived / Complete)
- [x] **Fuel Entry tab** — submit fuel logs with receipt, history list with pull-to-refresh
- [x] **Maintenance tab** — history list, mark-complete with proof photo, green FAB
- [x] **Report Issue tab** — description + optional photo, history list with status pills
- [x] **Emergency SOS tab** — location auto-fill, description + optional photo, history list
- [x] **Trip History tab** — completed trip cards with status, pull-to-refresh
- [x] **Notifications tab** — real-time alert cards
- [x] **Profile tab** — driver info, duty toggle, logout
- [x] **Custom truck loading animation** — animated truck drives across a road track (replaces `CircularProgressIndicator` app-wide)
- [x] Custom animations: `SmoothPageRoute`, `AnimatedListItem`, staggered list animations
- [x] Haptic feedback on key interactions
- [x] Location permission denied → in-app dialog with "Open Settings"
- [x] Network loss during GPS polling → quiet 5s retry
- [x] Trips screen: distinguishes "No active trip" (empty) from network error (retry)

### ✅ Recently Completed
- [x] **Role-Based Access Control (RBAC)** — `accounts/permissions.py` with 7 composable DRF permission classes; enforced across all fleet, dispatch, telemetry, and maintenance endpoints
- [x] **Backend unit test suite** — 24 tests passing (accounts: 13, vehicles: 11) — all pass with RBAC active
- [x] **Migration conflict resolution** — all 38 migrations apply cleanly on fresh DBs

### 🚧 Not Yet Started / Planned
- [ ] Firebase Cloud Messaging push notifications (mobile)
- [ ] Docker Compose full-stack deployment (Nginx + Gunicorn + Daphne)
- [ ] Frontend component tests (React/TypeScript)
- [ ] Flutter widget and integration tests
- [ ] User Acceptance Testing (UAT)
- [ ] Performance benchmarking (sub-2s dispatch @ 50 concurrent updates/sec)
- [ ] CI/CD pipeline (GitHub Actions)

---

## 📋 Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Python | 3.11+ | Tested on Windows with 3.x |
| Node.js | 18+ | For the React/Vite frontend |
| Flutter | 3.x (SDK ^3.11.5) | For the driver mobile app |
| Docker | Latest | For PostGIS + Redis containers |
| GDAL/GEOS | via OSGeo4W | Required for GeoDjango spatial fields |
| Git | Latest | |

---

## 🚀 Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/Sumit46p/Sarathi.git
cd Sarathi/sarathi
```

### 2. Start PostGIS (Docker)

```bash
docker run -d --name sarathi-db \
  -e POSTGRES_PASSWORD=devpass \
  -p 5433:5432 \
  postgis/postgis:16-3.4
```

for windows:
docker run -d --name sarathi-db -e POSTGRES_PASSWORD=devpass -p 5433:5432 postgis/postgis:16-3.4

> Port **5433** on host → 5432 inside the container (avoids conflicts with local PostgreSQL). Wait ~10 s for the database to initialise.

### 3. Start Redis (Docker Compose)

```bash
docker-compose -f docker-compose.redis.yml up -d
```

Starts Redis 7 Alpine with AOF persistence on port **6379**.

```bash
# Verify Redis is healthy
docker exec sarathi_redis redis-cli ping
# → PONG
```

### 4. Install GDAL / GEOS

#### Windows (OSGeo4W)
1. Download: https://download.osgeo.org/osgeo4w/v2/osgeo4w-setup.exe
2. **Express Install** → check **GDAL**
3. Default install: `C:\Users\<you>\AppData\Local\Programs\OSGeo4W`
4. Update `OSGEO4W` path in `sarthi_backend/settings.py` if different
5. Verify the GDAL DLL name (e.g., `gdal313.dll`) matches `GDAL_LIBRARY_PATH` in settings

#### Linux / macOS
```bash
sudo apt-get install gdal-bin libgdal-dev   # Debian/Ubuntu
brew install gdal                            # macOS
```

### 5. Python backend

```bash
# Create & activate virtual environment
python -m venv venv
.\venv\Scripts\activate          # Windows
source venv/bin/activate         # Linux/macOS

# Install dependencies
pip install -r requirements.txt

# Apply migrations
python manage.py migrate

# Create a superuser (first admin)
python manage.py createsuperuser

# Run development server
python manage.py runserver 0.0.0.0:8000
```

Backend available at: **http://localhost:8000**  
Admin panel: **http://localhost:8000/admin**

### 6. React frontend

```bash
cd frontend
npm install
npm run dev
```

Frontend available at: **http://localhost:5173**

### 7. Flutter driver app

If using a physical Android device or emulator connected via USB/ADB, forward port 8000 so the app can talk to `localhost:8000`:

```bash
adb reverse tcp:8000 tcp:8000
```

```bash
cd driver_app
flutter pub get
flutter run
```

Make sure a device/emulator is connected. The app connects to `http://127.0.0.1:8000/api/` (with `adb reverse`) or `http://<your-local-ip>:8000/api/`.

---

## 🎮 How to Operate the System

1. **System Startup:** Ensure PostGIS (port 5433) and Redis (port 6379) are running in Docker. Then start the Django backend (`python manage.py runserver`), the Vite frontend (`npm run dev`), and the Flutter app (`flutter run`).
2. **Admin/Dispatcher Dashboard:** Open `http://localhost:5173`. Log in with your admin/dispatcher credentials.
3. **Driver Workflow:** Open the Flutter app. Log in as a driver. Toggle **"On Duty"**. This updates the `is_available` status on the backend, provided you are not admin-blocked.
4. **Dispatching:**
   - In the React frontend, go to **Dispatch Workspace**. 
   - Enter a pickup location and destination. The system will use OSRM to preview the route, simplify the geometry for a clean map overlay, and evaluate candidates based on ETA and availability.
   - Click "Dispatch" on a recommended vehicle.
5. **Real-time Tracking:** Once dispatched, the driver receives an instant notification (via WebSockets/polling). As the driver moves, the app sends GPS points. The React dashboard updates the vehicle's position, ETA, and progress along the multi-waypoint OSRM route in the **Live Tracking** tab.
6. **Breakdown / Issues:** If a vehicle breaks down, the driver reports it in the app. The dispatcher can then authorize an "Emergency Recovery" from the dashboard, assigning a new vehicle to the breakdown coordinates.
7. **Fuel & Maintenance:** Drivers log fuel (now using `FuelLog` with receipt images) and complete maintenance tasks from the app. These immediately reflect in the Admin **Analytics** and Fuel/Maintenance tabs.

---

## 🗄️ Key API Endpoints

### Auth
| Method | URL | Description |
|--------|-----|-------------|
| `POST` | `/api/auth/login/` | Login (username or email) |
| `POST` | `/api/auth/token/refresh/` | Refresh JWT |
| `POST` | `/api/auth/register/` | Register new admin |
| `PATCH` | `/api/drivers/me/change-password/` | Driver password change |

### Fleet
| Method | URL | Description |
|--------|-----|-------------|
| `GET/POST` | `/api/vehicles/` | List / create vehicles |
| `GET/PUT/DELETE` | `/api/vehicles/<id>/` | Vehicle detail |
| `GET/POST` | `/api/drivers/` | List / create drivers |
| `GET` | `/api/drivers/me/` | Current driver profile |

### Dispatch
| Method | URL | Description |
|--------|-----|-------------|
| `POST` | `/api/dispatch/` | Create a dispatch |
| `GET` | `/api/dispatch/active/` | Current driver's active dispatch |
| `PATCH` | `/api/dispatch/<id>/` | Update dispatch status |
| `GET` | `/api/dispatch/export/` | CSV export |

### Trips & Tracking
| Method | URL | Description |
|--------|-----|-------------|
| `GET` | `/api/trips/` | Trip history |
| `GET` | `/api/trips/<id>/playback/` | GPS breadcrumbs for playback |
| `POST` | `/api/location/` | Submit GPS location |

### Driver Actions
| Method | URL | Description |
|--------|-----|-------------|
| `POST` | `/api/drivers/me/report-issue/` | Submit issue report |
| `POST` | `/api/emergency/requests/create/` | Emergency SOS |
| `GET/POST` | `/api/drivers/me/fuel-logs/` | Fuel log |
| `GET` | `/api/drivers/me/maintenance/` | Assigned maintenance |
| `POST` | `/api/drivers/me/maintenance/<id>/complete/` | Mark maintenance complete |

### Analytics & Reports
| Method | URL | Description |
|--------|-----|-------------|
| `GET` | `/api/analytics/` | Fleet analytics dashboard |
| `GET` | `/api/drivers/<id>/score/` | Driver safety score |
| `GET` | `/api/fuel-prices/` | Current NOC fuel prices |
| `GET` | `/api/expenses/report/pdf/` | Expense PDF report |

---

## 🛠️ Tech Stack

### Backend
| Package | Version | Purpose |
|---------|---------|---------|
| Django | 5.2 | Web framework |
| djangorestframework | 3.17 | REST API |
| djangorestframework-simplejwt | 5.3 | JWT auth |
| django-channels | — | WebSocket / ASGI |
| django-cors-headers | 4.9 | CORS |
| psycopg2-binary | 2.9 | PostgreSQL / PostGIS driver |
| redis | 5.0 | Redis client |
| django-redis | 5.4 | Redis cache backend |
| reportlab | 4.2 | PDF generation |
| beautifulsoup4 | 4.12 | NOC fuel price scraping |

### Frontend
| Package | Version | Purpose |
|---------|---------|---------|
| React | 19 | UI framework |
| TypeScript | 6 | Type safety |
| Vite | 8 | Build tool / dev server |
| react-router-dom | 7 | Client-side routing |
| axios | 1.18 | HTTP client |
| leaflet + react-leaflet | 1.9 / 5 | Interactive maps |
| recharts | 3 | Analytics charts |
| lucide-react | 1.24 | Icons |

### Flutter Driver App
| Package | Version | Purpose |
|---------|---------|---------|
| flutter_map | 8.3 | Leaflet maps in Flutter |
| geolocator | 14 | GPS location |
| google_fonts | 8.1 | Inter / custom typography |
| image_picker | 1.2 | Camera / gallery |
| flutter_secure_storage | 10.3 | Secure JWT storage |
| permission_handler | 12 | Runtime permissions |
| audioplayers | 6.1 | Notification sounds |
| http | 1.2 | HTTP API client |
| intl | 0.20 | Date / number formatting |

---

## 🎨 Design System (Flutter)

The driver app uses a centralized `AppTheme` (`lib/theme.dart`):

- **Primary**: Green (`#2E7D32`) — actions, FABs, status "active"
- **Error**: Red (`#C62828`) — emergency, alerts
- **Surface**: High-contrast white cards with shadows
- **Typography**: Inter (Google Fonts) throughout
- **Loading**: Custom `TruckLoader` animation — animated truck driving across a road track, replaces all `CircularProgressIndicator` page-level loaders

---

## 🔧 Development Notes

### Environment variables

Create a `.env` file (not committed) with:

```env
SECRET_KEY=your-django-secret-key
DEBUG=True
DB_HOST=localhost
DB_PORT=5433
DB_NAME=postgres
DB_USER=postgres
DB_PASSWORD=devpass
REDIS_URL=redis://localhost:6379/1
```

### Running OSRM (optional, for real routing)

By default the app falls back to straight-line distance if OSRM is unavailable. To run OSRM locally:

```bash
docker run -t -v $(pwd)/osrm-data:/data osrm/osrm-backend osrm-routed \
  --algorithm mld /data/your-region.osrm
```

Update `OSRM_BASE_URL` in `sarthi_backend/settings.py`.

### Running the WebSocket server

Django Channels requires an ASGI server (Daphne or Uvicorn):

```bash
daphne -b 0.0.0.0 -p 8000 sarthi_backend.asgi:application
# or
uvicorn sarthi_backend.asgi:application --host 0.0.0.0 --port 8000
```

---

## 📁 Project Structure (detail)

```
sarathi/
├── accounts/
│   ├── models.py            # Organization, UserProfile
│   ├── serializers.py
│   └── views.py             # Login, register, password reset, rate limiting
├── vehicles/
│   ├── models.py            # Vehicle, Driver, Dispatch, LocationRecord,
│   │                        #   MaintenanceRecord, FuelEntry, IssueReport,
│   │                        #   EmergencyRequest, Alert, Rule, Route, Rental
│   ├── views.py             # All REST endpoints + WebSocket consumers
│   ├── dispatch_engine.py   # Multi-factor dispatch ranking
│   ├── rules_engine.py      # Geofencing / speed / alert policies
│   ├── cache_utils.py       # Jittered TTL helper
│   └── osrm.py              # OSRM routing client
├── sarthi_backend/
│   ├── settings.py          # Django config (PostGIS, Redis, Channels, JWT)
│   ├── urls.py
│   ├── asgi.py              # Channels ASGI config
│   └── wsgi.py
├── frontend/src/
│   ├── components/
│   │   ├── DispatchWorkspace.tsx
│   │   ├── LiveTrackingTab.tsx
│   │   ├── FuelTab.tsx
│   │   ├── MaintenanceTab.tsx
│   │   ├── IssuesTab.tsx
│   │   ├── RoutesTab.tsx
│   │   ├── RentalsTab.tsx
│   │   └── NotificationBell.tsx
│   └── hooks/
│       └── useAdminNotifications.ts
└── driver_app/lib/
    ├── screens/
    │   ├── dashboard_screen.dart
    │   ├── trips_screen.dart
    │   ├── trip_history_screen.dart
    │   ├── fuel_entry_screen.dart
    │   ├── maintenance_screen.dart
    │   ├── report_issue_screen.dart
    │   ├── emergency_screen.dart
    │   ├── notifications_screen.dart
    │   └── profile_screen.dart
    ├── widgets/
    │   ├── truck_loader.dart     # Custom animated truck loading widget
    │   ├── custom_buttons.dart
    │   └── stat_card.dart
    ├── services/
    │   └── api_service.dart      # All HTTP + JWT logic
    ├── utils/
    │   └── animations.dart       # SmoothPageRoute, AnimatedListItem
    └── theme.dart                # AppTheme color tokens + text styles
```

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit your changes: `git commit -m 'feat: add your feature'`
4. Push to the branch: `git push origin feature/your-feature`
5. Open a Pull Request

## 🧪 Testing

### Test Results (October 2026)

All backend tests pass successfully across both Django apps:

| App | Tests | Passed | Failed | Errors |
|-----|-------|--------|--------|--------|
| `accounts` | 13 | **13** | 0 | 0 |
| `vehicles` | 11 | **11** | 0 | 0 |
| **Total** | **24** | **24** | 0 | 0 |

```
Ran 24 tests in 18.518s
OK
```

---

### How to Run Tests

#### Prerequisites
- PostgreSQL + PostGIS running (Docker on port 5433, see Quick Start)
- Redis running (Docker on port 6379)
- Python dependencies installed (`pip install -r requirements.txt`)

> **Note:** The test runner creates and destroys a temporary `test_postgres` database automatically. If it already exists from a previous run, Django will prompt you to delete it — type `yes` to proceed.

#### Run all backend tests
```bash
python manage.py test
```

#### Run by app (recommended for faster feedback)
```bash
python manage.py test accounts
python manage.py test vehicles
```

#### Run with verbose output (shows each test name + result)
```bash
python manage.py test accounts --verbosity=2
python manage.py test vehicles --verbosity=2
```

#### Keep the test database between runs (faster re-runs)
```bash
python manage.py test --keepdb
```

#### Run with coverage report
```bash
pip install coverage
coverage run manage.py test
coverage report -m
coverage html   # Generates htmlcov/index.html
```

---

### Test Structure

#### `accounts/tests.py` — 13 tests

| Class | Tests | What is verified |
|-------|-------|-----------------|
| `OrganizationModelTestCase` | 2 | Model creation, default status field |
| `ProfileModelTestCase` | 5 | Profile fields, `is_online` property, 5-min threshold boundary |
| `GetOrganizationNameTestCase` | 2 | Org name resolution (no profiles, with admin profile) |
| `AuthenticationTestCase` | 2 | Unauthenticated 401/403, user↔profile OneToOne relationship |
| `RoleBasedAccessTestCase` | 2 | Role assignment, org membership for SUPER_ADMIN and DRIVER |

#### `vehicles/tests.py` — 10 tests

| Class | Tests | What is verified |
|-------|-------|-----------------|
| `HaversineDistanceTestCase` | 3 | Same-point (0 km), Kathmandu↔Pokhara (~145 km), symmetry |
| `ModelTestCase` | 3 | Organization, Driver, Vehicle creation + GPS staleness |
| `DispatchEngineTestCase` | 1 | Emergency vs normal priority weight difference |
| `MaintenanceTestCase` | 2 | Record creation, completion workflow |
| `APIEndpointTestCase` | 1 | Authenticated vehicle list returns 200 OK |

---

### Migration Issues Fixed (October 2026)

Two issues were identified and resolved before the test suite was stabilized:

#### 1. Missing DB columns (`fuel_type`, `photo`)
Migration `0026` was recorded as applied but the `fuel_type` and `photo` columns were never added to the live PostgreSQL schema. This caused migration `0030`'s data migration to crash. Fixed by adding the columns directly:

```sql
ALTER TABLE vehicles_vehicle
  ADD COLUMN IF NOT EXISTS fuel_type VARCHAR(20) DEFAULT 'petrol',
  ADD COLUMN IF NOT EXISTS photo VARCHAR(100) NULL;
```

Then `python manage.py migrate` applied migrations `0030` through `0038` cleanly.

#### 2. `UniqueConstraintViolation` on Profile in tests
`accounts/signals.py` registers a `post_save` signal that **auto-creates a `Profile`** for every new `User` via `get_or_create`. Tests that then called `Profile.objects.create(user=...)` for the same user raised a `unique constraint` violation.

**Pattern to follow in all tests:**
```python
# ❌ Wrong — raises IntegrityError if signal already created the profile
profile = Profile.objects.create(user=user, organization=org, role="ADMIN")

# ✅ Correct — work with the signal-created profile
profile = user.profile       # access auto-created profile
profile.organization = org
profile.role = "ADMIN"
profile.save()
```

---

### Feature Checklist Update

- [x] **Automated unit test suite** — accounts app (13 tests) and vehicles app (10 tests)
- [x] **Migration conflict resolution** — all 38 migrations apply cleanly on a fresh DB
- [ ] Frontend component tests (React/TypeScript) — planned
- [ ] Flutter widget/integration tests — planned
- [ ] CI/CD pipeline (GitHub Actions) — planned

---

## 📄 License

This project is private. All rights reserved.

---

*Built with ❤️ for smarter fleet operations.*
