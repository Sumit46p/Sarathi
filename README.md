# 🚑 Sarthi — Smart Vehicle Dispatch System

Sarthi is an intelligent, location-aware vehicle dispatch platform built for
emergency and municipal services. It enables real-time tracking and routing of
ambulances, logistics trucks, and municipal vehicles using geospatial data,
helping dispatchers assign the nearest available vehicle to any request. The
backend is powered by Django + PostGIS with OSRM real-road routing, a React
dashboard for dispatchers/admins, a Flutter mobile app for drivers, and a
**Redis-backed real-time WebSocket notification system** for instant alerts.

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
- [x] JWT login (username/email + password + organization_name)
- [x] **On Duty toggle** → sets `Driver.is_on_duty` (requests location permission, sends immediate GPS fix + 5s polling)
- [x] Driver's assigned vehicle shown from `/api/drivers/me/`
- [x] **Trips tab**: live dispatch route on a map + status transitions (Accept / En Route / Arrived / Complete)
- [x] **First-login password change** (forced when `requires_password_change` is true)
- [x] **Report Issue** screen: submit descriptions + optional photo via `POST /api/drivers/me/report-issue/`
- [x] **Emergency SOS** screen: send emergency requests with location, description, and photo via `POST /api/emergency/requests/create/`
- [x] **Maintenance Request** screen: request maintenance with description and image via `POST /api/drivers/me/maintenance-request/`
- [x] Profile, Alerts, SOS placeholders

### Implemented (completed in this cycle)
- [x] Maintenance monitoring + scheduled service alerts (CRUD, overdue flagging, dashboard UI)
- [x] Maintenance tab in frontend (vehicle-filtered table, status badges, mark-complete, delete)
- [x] Removed Firebase/`drivers` app — standardized on Django REST + JWT (no separate `drivers` app)
- [x] Active dispatch endpoint (`GET /api/dispatch/active/`) — returns owner's latest active dispatch with live OSRM route geometry
- [x] Dashboard polls active dispatch every 5s and renders the live route as a green polyline on the map
- [x] Fixed vehicle availability bug: `has_active_dispatch` method call in `is_available` derivation
- [x] **Driver password change flow**: `requires_password_change` flag forces first-login password reset (`PATCH /api/drivers/me/change-password/`)
- [x] **Driver Report Issue feature**: backend `IssueReport` model + `POST /api/drivers/me/report-issue/` (multipart, optional photo); Flutter `ReportIssueScreen` with description, camera/gallery upload, submit confirmation
- [x] **Flutter UI enhancements**: custom animations (`SmoothPageRoute`, `AnimatedListItem`), splash screen animation, haptic feedback, staggered list animations, improved bottom nav, polished cards/buttons
- [x] **Admin-facing issue report view**: backend `IssueReport` now uses `status` workflow (`open` → `acknowledged` → `resolved`); admin endpoints `GET /api/issues/` (owner-scoped list) and `PATCH /api/issues/<id>/` (status update); frontend `IssuesTab` with photo thumbnails, status badges, Acknowledge/Resolve actions, and open-count badge on sidebar nav; fleet table shows warning indicator on vehicles with open driver issues
- [x] **Maintenance completion tracking**: `MaintenanceRecord` model now includes `proof_image`, `completed_by` (Driver FK), and `completion_notes` fields for driver-submitted completion evidence
- [x] **FuelLog model**: New model for tracking fuel expenses with vehicle, driver, amount, odometer reading, receipt image, and automatic timestamp
- [x] **FuelEntry model**: Alternative fuel tracking with detailed metrics (liters, cost_per_liter, total_cost, odometer_km, notes)
- [x] **Driver maintenance endpoints**: `GET /api/drivers/me/maintenance/` (list assigned vehicle maintenance) and `POST /api/drivers/me/maintenance/<id>/complete/` (mark complete with proof image and notes)
- [x] **Driver fuel log endpoints**: `POST /api/drivers/me/fuel-logs/` (submit fuel log with receipt) and `GET /api/fuel-logs/` (admin view all fuel logs)
- [x] **Automatic maintenance recurrence**: `_auto_create_next_record()` helper automatically creates next recurring maintenance record when one is completed (supports both time-based and km-based recurrence)
- [x] **MaintenanceRecordDetailView enhancement**: `perform_update` now calls recurrence helper when status changes to 'completed'

### Robustness & Polish Pass
- [x] **Backend**: Case-insensitive organization name matching across login, password reset, and identity verification flows
- [x] **Backend**: Fixed DriverMeSerializer KeyError by including `requires_password_change` in duty endpoint response
- [x] **React Dashboard**: Loading skeletons on all data-fetching components
- [x] **React Dashboard**: Empty states with clear messaging
- [x] **React Dashboard**: Error banners with dismiss & retry buttons on all CRUD operations
- [x] **React Dashboard**: Success/error toast notifications on create/update/delete actions
- [x] **Flutter Driver App**: Location permission denied shows in-app dialog with "Open Settings" button
- [x] **Flutter Driver App**: Network loss during location polling retries quietly every 5s
- [x] **Flutter Driver App**: Trips screen distinguishes "No active trip" (empty state) from network error (retry button)
- [x] All error handling maintains API contracts — no breaking changes to endpoints or responses

### Fuel Management & Expense Tracking
- [x] **NOC fuel price integration**: Automatic scraping of petrol/diesel prices from Nepal Oil Corporation (updated daily)
- [x] **Fuel price API**: `GET /api/fuel-prices/` returns current fuel prices with 24-hour caching
- [x] **FuelTab redesign**: Rebuilt with dashboard design system
- [x] **Fuel summary metrics**: Total entries, total cost, this-month cost, distinct vehicles fuelled
- [x] **Vehicle filter + search**: Filter fuel records by vehicle, search by vehicle/driver name
- [x] **Receipt preview modal**: Click receipt thumbnail to view full-size image in modal

### Exports, Security & Analytics
- [x] **Auth rate limiting**: DRF throttles on login (30/min), register (10/hour), password reset (5/hour), and identity verification (20/hour) per IP
- [x] **Dispatch CSV export**: `GET /api/dispatch/export/` downloads org-scoped dispatch history with optional filters
- [x] **Expense PDF report**: `GET /api/expenses/report/pdf/` generates an expense summary PDF (fuel + maintenance, per-vehicle breakdown)
- [x] **Analytics: fuel efficiency**: `analytics_dashboard` now reports `km_per_liter` per vehicle
- [x] **Analytics: driver performance**: Per-driver trip totals, acceptance rate, completion counts, and color-coded safety score
- [x] **Driver safety score**: `GET /api/drivers/<id>/score/` — 0–100 score based on harsh driving events over last 30 days
- [x] **Harsh driving event detection**: Server-side heuristic detects `harsh_accel` / `harsh_brake` / `harsh_turn` from consecutive GPS breadcrumbs

### Trip History & Route Playback
- [x] **Live ETA + route progress**: Active dispatch returns `progress_percent`, `remaining_distance_km`, and `eta_min`
- [x] **GPS breadcrumb recording**: Every location fix is stored in `LocationRecord` model
- [x] **Trip history API**: `GET /api/trips/` lists finished dispatches
- [x] **Route playback API**: `GET /api/trips/<id>/playback/` returns time-ordered GPS breadcrumbs
- [x] **Frontend Trip History tab**: Animated route playback with play/pause, speed control, scrubber

### 🆕 Redis Caching & Real-Time WebSocket Notifications
- [x] **Redis infrastructure**: `docker-compose.redis.yml` with Redis 7 Alpine + AOF persistence enabled
- [x] **Django Redis cache backend**: `django-redis` configured for CACHES (db=1) with `IGNORE_EXCEPTIONS=True` (graceful fallback to in-memory on Redis failure)
- [x] **Redis session store**: Sessions stored in Redis (db=1) with **12-hour TTL**
- [x] **JWT session jitter**: Each login response includes `expires_in` with ±5-minute random jitter to prevent thundering-herd stampedes on mass token expiry
- [x] **Cache jitter utility** (`vehicles/cache_utils.py`): `jittered_ttl(base, jitter)` applied to all `cache.set()` calls — OSRM routes (20–40s), GPS breadcrumbs (30–90s)
- [x] **DRF throttle cache**: Rate-limiting (login, register, etc.) now persists across server restarts via Redis
- [x] **Django Channels**: Upgraded ASGI to `ProtocolTypeRouter` with a JWT-authenticated `NotificationConsumer`
- [x] **WebSocket channel groups**: Each user joins `user_notifications_<id>` (personal) and `org_notifications_<org>` (organization-wide) groups on connect
- [x] **Real-time push signals**: `post_save` signals on `IssueReport`, `EmergencyRequest`, `MaintenanceRecord`, and `Notification` instantly push JSON payloads to the org admin group via Redis channel layer
- [x] **Frontend WebSocket hook** (`useAdminNotifications.ts`): Connects via `ws://localhost:8000/ws/notifications/?token=<jwt>`, reconnects automatically on disconnect
- [x] **Smart polling fallback**: Dashboard 5-second polling loop skips `issues`, `emergencies`, and `maintenance` endpoints while WebSocket is healthy; falls back to polling immediately on disconnect
- [x] **Instant targeted refetch**: WebSocket events trigger immediate refetch of only the affected data type (no full dashboard refresh)
- [x] **NotificationBell integration**: Bell icon wired to the hook with live `markAsRead` and `deleteNotification` actions

### Not Yet Started / Partial
- [ ] Role-based access control *within* an organization (one admin = one org; no dispatcher/viewer sub-roles yet)
- [ ] Firebase Cloud Messaging push notifications (mobile)
- [ ] Docker Compose full-stack deployment (Nginx + Gunicorn + Daphne)
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
| Docker | Latest | For PostGIS + Redis containers |
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

### 3. Start Redis (Docker Compose)

Redis is required for caching, session storage, and WebSocket channel messaging.

```bash
docker-compose -f docker-compose.redis.yml up -d
```

This starts Redis 7 Alpine with AOF (Append-Only File) persistence on port **6379**.

To verify Redis is healthy:
```bash
docker exec sarathi_redis redis-cli ping
# Expected output: PONG
```

### 4. Install GDAL / GEOS system libraries

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

### 5. Create and activate virtual environment

```bash
python -m venv venv

# Windows (PowerShell)
.\venv\Scripts\Activate.ps1

# macOS / Linux
source venv/bin/activate
```

### 6. Install Python dependencies

```bash
pip install -r requirements.txt
```

Key packages now included: `channels`, `channels-redis`, `daphne`, `redis`, `django-redis`.

### 7. Run database migrations

```bash
python manage.py migrate
```

### 8. Create a superuser

```bash
python manage.py createsuperuser
```

Enter a username, email, and password when prompted.

### 9. Run the development server

> **⚠️ Important:** The server must be started via **Daphne** (or `manage.py runserver` which auto-detects Django Channels) to support WebSocket connections.

```bash
python manage.py runserver
```

Visit:
- **http://localhost:8000/admin/** — Django admin (log in with your superuser)
- **http://localhost:8000/api/vehicles/** — Browsable API (DRF)
- Add test vehicles using the **map picker** in admin, or via the API

### 10. Set up the React frontend

```bash
cd frontend
npm install
npm run dev
```

Visit **http://localhost:5173** to see the live vehicle map and dispatch console.

### 11. Run the Flutter driver app

The Flutter driver app runs on Android emulators, physical Android devices, or iOS devices.
Ensure the Django backend is running on `http://localhost:8000` before starting the app.

```bash
cd driver_app
flutter pub get
flutter run
```

Log in with a **driver account** created from the dashboard (Admin → Drivers → Add driver, with username + password). The driver's On Duty toggle and Trips tab connect to the same backend.

#### Common Issues & Network Configuration

**Error: "No internet connection" or "Can't reach 127.0.0.1:8000"**

The Flutter app uses `http://127.0.0.1:8000` to connect to the backend. Depending on your setup, you may need to configure the network tunnel:

##### **Android Emulator**
```bash
adb reverse tcp:8000 tcp:8000
```

##### **Physical Android Device** (USB connected)
1. Connect your device via USB
2. Enable USB debugging in Developer Options
3. Run this **every time you connect**:
   ```bash
   adb reverse tcp:8000 tcp:8000
   ```

##### **iOS Device/Simulator**
Edit `driver_app/lib/services/api_service.dart` and replace `127.0.0.1` with your local IP address.

---

## 🗺️ Running the Full Stack

To see everything working together, you need **3 terminals** running simultaneously:

### Terminal 1 — Redis
```bash
docker-compose -f docker-compose.redis.yml up -d
```

### Terminal 2 — Django API server (with WebSocket support)
```bash
cd Sarathi
.\venv\Scripts\Activate.ps1      # Windows
python manage.py runserver
```

### Terminal 3 — React frontend (Vite dev server)
```bash
cd Sarathi/frontend
npm run dev
```

### Terminal 4 — Vehicle simulator (optional, or use the Flutter driver app)
```bash
cd Sarathi
.\venv\Scripts\Activate.ps1      # Windows
python scripts/simulate_vehicle.py 1
```

Then open **http://localhost:5173**. Open the browser devtools console — you should see `Admin WebSocket connected`. When a new emergency, issue, or maintenance event occurs, a notification appears **instantly** in the bell without waiting for the polling interval.

---

## ⚡ Real-Time Architecture

```
Driver App / Admin Action
        ↓
Django Model Save (IssueReport / EmergencyRequest / MaintenanceRecord)
        ↓
post_save Signal (vehicles/signals.py)
        ↓
channel_layer.group_send → Redis Channel Layer (db=2)
        ↓
NotificationConsumer (vehicles/consumers.py)
        ↓
WebSocket → Browser (useAdminNotifications hook)
        ↓
NotificationBell update + targeted data refetch
```

**Fallback behavior:** If the WebSocket disconnects (Redis restart, network blip), the frontend automatically falls back to 5-second polling for issues, emergencies, and maintenance. On reconnect, it immediately re-syncs all data.

---

## 🔌 WebSocket Endpoint

| URL | Auth | Description |
|-----|------|-------------|
| `ws://localhost:8000/ws/notifications/?token=<jwt>` | JWT query param | Real-time notification stream for the logged-in user |

### Channel Groups

| Group Name | Members | Events Received |
|-----------|---------|----------------|
| `user_notifications_<user_id>` | Individual user | Personal notifications (`Notification` model) |
| `org_notifications_<org_name>` | All admins in same org | Issues, Emergencies, Maintenance records |

---

## 🔌 API Endpoints

All endpoints are under the project root (`sarthi_backend/urls.py` → app routers).
Auth: `Authorization: Bearer <access_token>`.

### Auth (`/api/auth/`)
| Method | URL | Description |
|--------|-----|-------------|
| POST | `/api/auth/login/` | Obtain JWT (accepts `username` **or** `email` + `password`). Response includes `expires_in` (seconds, with ±5m jitter) |
| POST | `/api/auth/login/refresh/` | Refresh access token |
| POST | `/api/auth/register/` | Register a new admin/user (username, email, password, organization_name) |
| GET | `/api/auth/me/` | Current user + organization name |

### Vehicles (`/api/`)
| Method | URL | Description |
|--------|-----|-------------|
| GET | `/api/vehicles/` | List vehicles for current org |
| POST | `/api/vehicles/` | Create a vehicle |
| GET | `/api/vehicles/<id>/` | Vehicle detail |
| PATCH | `/api/vehicles/<id>/` | Update (incl. `admin_blocked`) |
| DELETE | `/api/vehicles/<id>/` | Remove a vehicle |
| POST | `/api/vehicles/<id>/update-location/` | Update GPS location `{"lat":.,"lng":..}` |
| POST | `/api/vehicles/<id>/assign-driver/` | Assign a driver `{"driver_id": <id>}` |
| POST | `/api/vehicles/<id>/dispatch/transition/` | **Admin** advances the active dispatch |

### Dispatch
| Method | URL | Description |
|--------|-----|-------------|
| POST | `/api/dispatch/` | Dispatch nearest available vehicle `{"lat":.,"lng":.,"vehicle_type":..}` |
| GET | `/api/dispatch/active/` | Owner's latest active dispatch with live route geometry |
| GET | `/api/dispatch/stats/` | Dispatch counts by status + daily breakdown (last 30 days) |
| GET | `/api/dispatch/export/` | CSV download of dispatch history (`?status=&start_date=&end_date=`) |

### Drivers (`/api/`)
| Method | URL | Description |
|--------|-----|-------------|
| GET | `/api/drivers/` | List drivers for current org |
| POST | `/api/drivers/` | Create a driver **with login credentials** |
| GET | `/api/drivers/me/` | Current driver's profile + assigned vehicle + `is_on_duty` |
| PATCH | `/api/drivers/me/duty/` | Set `{"is_on_duty": true\|false}` |
| PATCH | `/api/drivers/me/change-password/` | First-login password change |
| POST | `/api/drivers/me/report-issue/` | Submit an issue report with optional photo |
| POST | `/api/drivers/me/maintenance-request/` | Submit a maintenance request |
| GET | `/api/drivers/me/dispatch/` | Active dispatch for the driver's vehicle |
| POST | `/api/drivers/me/dispatch/transition/` | **Driver** advances the dispatch |
| GET | `/api/drivers/<id>/score/` | Driver safety score (0–100 over last 30 days) |
| GET | `/api/drivers/me/trip-history/` | Driver's finished trips |

### Trips (`/api/trips/`)
| Method | URL | Description |
|--------|-----|-------------|
| GET | `/api/trips/` | Finished dispatches (completed/cancelled/rejected), org-scoped |
| GET | `/api/trips/<id>/playback/` | Time-ordered GPS breadcrumbs for route replay |

### Maintenance (`/api/`)
| Method | URL | Description |
|--------|-----|-------------|
| GET | `/api/maintenance/` | List maintenance records |
| POST | `/api/maintenance/` | Create a record |
| PATCH | `/api/maintenance/<id>/` | Update (mark completed) |
| DELETE | `/api/maintenance/<id>/` | Remove |
| GET | `/api/maintenance/upcoming/` | Due in next 30 days |

### Emergency (`/api/emergency/`)
| Method | URL | Description |
|--------|-----|-------------|
| POST | `/api/emergency/requests/create/` | Driver submits emergency SOS |
| GET | `/api/emergency/requests/` | Admin lists all emergency requests |
| POST | `/api/emergency/requests/<id>/dispatch/` | Admin dispatches vehicle to emergency |
| POST | `/api/emergency/requests/<id>/resolve/` | Admin marks emergency resolved |
| GET | `/api/emergency/notifications/unread-count/` | Count of unread emergency notifications |

### Reports & Exports (`/api/`)
| Method | URL | Description |
|--------|-----|-------------|
| GET | `/api/expenses/summary/` | Aggregated expense stats |
| GET | `/api/expenses/report/pdf/` | PDF download of expense summary |
| GET | `/api/dispatch/export/` | CSV download of dispatch history |

---

## 🚗 Location Simulator

The simulator script performs a **random walk** near Jhapa, Nepal, calling the
`update-location` endpoint every 4 seconds to simulate a vehicle moving in
real time.

```bash
python scripts/simulate_vehicle.py 1
# Optional: faster updates
python scripts/simulate_vehicle.py 1 --interval 2
```

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | Django 5.2 + Django REST Framework |
| Auth | `djangorestframework-simplejwt` (JWT) |
| Geospatial | GeoDjango + PostGIS + GDAL/GEOS |
| Database | PostgreSQL 16 + PostGIS 3.4 (Docker) |
| Cache & Sessions | Redis 7 (Docker) + `django-redis` |
| WebSockets | Django Channels 4 + `channels-redis` + Daphne |
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
├── docker-compose.redis.yml        # Redis 7 Alpine with AOF persistence
├── scripts/
│   └── simulate_vehicle.py        # Location simulator (random walk)
├── sarthi_backend/                 # Django project config
│   ├── settings.py                 # DB, GDAL, Redis, CORS, Channels, installed apps
│   ├── urls.py                     # Root routes
│   ├── asgi.py                     # ASGI: ProtocolTypeRouter for HTTP + WebSocket
│   ├── routing.py                  # WebSocket URL patterns (ws/notifications/)
│   └── wsgi.py
├── vehicles/                       # Vehicle tracking + dispatch + drivers
│   ├── models.py                   # Vehicle, DispatchRequest, Driver, IssueReport,
│   │                               #   MaintenanceRecord, Notification, EmergencyRequest,
│   │                               #   LocationRecord, DrivingEvent
│   ├── serializers.py
│   ├── views.py                    # CRUD, nearest, dispatch, driver_me, signals, etc.
│   ├── urls.py
│   ├── osrm.py                     # OSRM real-road routing helper (with cache jitter)
│   ├── consumers.py                # WebSocket NotificationConsumer + JWTAuthMiddleware
│   ├── signals.py                  # post_save signals → WebSocket push for all alert models
│   ├── cache_utils.py              # jittered_ttl() utility for thundering-herd prevention
│   └── migrations/
├── accounts/                       # JWT auth + user profiles
│   ├── models.py                   # Profile (org type, is_online)
│   ├── serializers.py
│   ├── views.py                    # LoginView (with expires_in jitter), RegisterView
│   └── urls.py
├── driver_app/                     # Flutter mobile app (drivers)
│   ├── lib/
│   │   ├── services/api_service.dart
│   │   ├── screens/
│   │   │   ├── dashboard_screen.dart
│   │   │   ├── trips_screen.dart
│   │   │   ├── report_issue_screen.dart
│   │   │   ├── emergency_screen.dart
│   │   │   ├── maintenance_screen.dart
│   │   │   ├── trip_history_screen.dart
│   │   │   └── profile_screen.dart
│   │   ├── theme.dart
│   │   └── main.dart
│   └── pubspec.yaml
├── frontend/                       # React + TypeScript + Vite (dispatcher console)
│   ├── src/
│   │   ├── api/auth.ts
│   │   ├── components/
│   │   │   ├── NotificationBell.tsx  # Real-time notification bell
│   │   │   ├── MaintenanceTab.tsx
│   │   │   ├── IssuesTab.tsx
│   │   │   ├── FuelTab.tsx
│   │   │   ├── TripsTab.tsx
│   │   │   ├── AnalyticsDashboard.tsx
│   │   │   └── ThemeToggle.tsx
│   │   ├── hooks/
│   │   │   ├── useAdminNotifications.ts  # WebSocket hook + polling fallback
│   │   │   └── useNotifications.ts       # Driver-side WS notifications (future)
│   │   ├── pages/
│   │   │   ├── Dashboard.tsx             # Fleet + Dispatch + Drivers + all tabs
│   │   │   ├── Login.tsx
│   │   │   └── Signup.tsx
│   │   ├── App.tsx
│   │   └── main.tsx
│   ├── package.json
│   └── vite.config.ts
└── ...
```

---

## 👥 Team

Built by a team of 4 students. See GitHub contributors for details.
