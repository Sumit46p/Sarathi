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
- [ ] REST API endpoints (DRF)
- [ ] React frontend dashboard
- [ ] OSRM routing integration
- [ ] Flutter mobile app

---

## 📋 Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Python | 3.11+ | Tested with 3.x on Windows |
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
- Add test vehicles using the **map picker** on the Vehicle form

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | Django 6.0 + Django REST Framework |
| Geospatial | GeoDjango + PostGIS + GDAL/GEOS |
| Database | PostgreSQL 16 + PostGIS 3.4 (Docker) |
| API | Django REST Framework (planned) |
| Frontend | React (planned) |
| Routing | OSRM (planned) |
| Mobile | Flutter (planned) |

---

## 📁 Project Structure

```
Sarathi/
├── manage.py
├── requirements.txt
├── sarthi_backend/        # Django project config
│   ├── settings.py        # DB, GDAL paths, installed apps
│   ├── urls.py
│   ├── wsgi.py
│   └── asgi.py
└── vehicles/              # Vehicle tracking app
    ├── models.py          # Vehicle model with PointField
    ├── admin.py           # GIS admin with map picker
    └── migrations/
        └── 0001_initial.py
```

---

## 👥 Team

Built by a team of 4 students. See GitHub contributors for details.
