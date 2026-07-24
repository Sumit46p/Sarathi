# 👤 Creating & Managing Driver Accounts

This guide explains how to create driver accounts and help drivers log into the Flutter mobile app.

## Why This Matters

The error **"No active account found with the given credentials"** means:
- ✅ The network connection is working (app reached the backend)
- ❌ But the driver account doesn't exist in the database yet

**Drivers cannot self-sign up** — only admins can create driver accounts with login credentials.

---

## Quick Start: 5 Steps to Get a Driver Logging In

### Step 1: Ensure Backend & Frontend are Running

**Terminal 1 — Backend:**
```bash
cd Sarathi
.\venv\Scripts\Activate.ps1      # Windows
python manage.py runserver
```

**Terminal 2 — React Frontend:**
```bash
cd Sarathi/frontend
npm run dev
```

Visit **http://localhost:5173** and log in with your admin credentials.

### Step 2: Create a Vehicle (if you haven't already)

1. Click the **Vehicles** tab
2. Click the **Add vehicle** button
3. Fill in:
   - **Name**: e.g., "Ambulance-01"
   - **Type**: e.g., "ambulance" (from dropdown)
   - **Location**: Click on the map to set GPS coordinates
4. Click **Save**

### Step 3: Create a Driver Account

1. Click the **Drivers** tab in the dashboard
2. Click the **Add driver** button
3. Fill in the form:
   - **Name**: e.g., "John Doe"
   - **Phone**: e.g., "9876543210"
   - **License Number**: e.g., "DL-12345"
   - **Username**: e.g., "john" ← **This is the login username**
   - **Password**: e.g., "SecurePass123!" ← **Initial password**
4. Click **Save**

✅ Driver account is now created!

### Step 4: Assign Driver to a Vehicle (Optional)

1. Go to the **Vehicles** tab
2. Find the vehicle you created
3. Click **Assign Driver** in the Actions column
4. Select the driver from the dropdown
5. Click **Assign**

The driver's On Duty toggle will now control this vehicle's availability.

### Step 5: Driver Logs Into Flutter App

On the **Flutter driver app** (running on emulator or phone):

1. **Username**: Enter the username you created (e.g., "john")
2. **Password**: Enter the password you set (e.g., "SecurePass123!")
3. Tap **Login**

✅ Driver is now logged in!

**On first login**, the driver will be prompted to change their password (this is forced).

---

## Creating Multiple Drivers via API (curl)

If you prefer the command line:

### Step 1: Get Your Admin JWT Token

```bash
curl -X POST http://localhost:8000/api/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "yourAdminPassword"}'
```

Response:
```json
{
  "access": "eyJ0eXAiOiJKV1QiLCJhbGc...",
  "refresh": "eyJ0eXAiOiJKV1QiLCJhbGc..."
}
```

Copy the `access` token.

### Step 2: Create a Driver

Replace `ADMIN_TOKEN` with the token from Step 1:

```bash
curl -X POST http://localhost:8000/api/drivers/ \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ADMIN_TOKEN" \
  -d '{
    "name": "John Doe",
    "phone_number": "9876543210",
    "license_number": "DL-12345",
    "username": "john",
    "password": "SecurePass123!"
  }'
```

Response:
```json
{
  "id": 1,
  "user": {
    "username": "john",
    "email": null
  },
  "name": "John Doe",
  "phone_number": "9876543210",
  "license_number": "DL-12345",
  "is_on_duty": false,
  "assigned_vehicle": null
}
```

✅ Driver created! Username is **"john"**, password is **"SecurePass123!"**

---

## Verifying Driver Exists

### Via Django Admin

1. Go to **http://localhost:8000/admin/**
2. Log in with your superuser
3. Go to **Drivers** → you should see your driver listed

### Via API

```bash
curl -X GET http://localhost:8000/api/drivers/ \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN"
```

---

## Common Issues & Fixes

### "No active account found with the given credentials"

**Cause**: Driver account doesn't exist or username is spelled wrong.

**Fix**:
1. Check Django admin → Users → verify the driver username exists
2. Check password is spelled correctly (case-sensitive)
3. Create the driver using the steps above

### "Network error: No internet connection"

**Cause**: App can't reach the backend.

**Fix** (for Android emulator):
```bash
adb reverse tcp:8000 tcp:8000
```

Then restart the app. See README.md for other device types.

### "App crashes after login"

**Cause**: Backend isn't returning driver profile data.

**Fix**:
1. Check backend logs: `python manage.py runserver` terminal
2. Verify the driver was assigned to a vehicle (or go to Django admin and check)
3. Restart the backend: `python manage.py runserver`

### Driver sees "No assigned vehicle"

**Cause**: Driver account exists but isn't assigned to any vehicle.

**Fix**:
1. In the dashboard, go to **Vehicles**
2. Find a vehicle and click **Assign Driver**
3. Select the driver from the dropdown
4. Click **Assign**
5. Restart the Flutter app

---

## Testing the Full Flow

1. **Create admin account** (if you haven't):
   ```bash
   python manage.py createsuperuser
   ```

2. **Run backend + frontend**:
   ```bash
   # Terminal 1
   python manage.py runserver
   
   # Terminal 2
   cd frontend && npm run dev
   ```

3. **Log in as admin** at http://localhost:5173

4. **Create a test vehicle** in the Vehicles tab

5. **Create a test driver** in the Drivers tab:
   - Username: `testdriver`
   - Password: `TestPass123!`

6. **Assign driver to vehicle**

7. **Open Flutter app** (emulator/phone with `adb reverse tcp:8000 tcp:8000` if Android)

8. **Login with**:
   - Username: `testdriver`
   - Password: `TestPass123!`

9. **Driver changes password** on first login

10. **Driver goes On Duty** → vehicle becomes "Available" on dashboard

11. **Dispatch a vehicle** → driver sees it on Trips tab

✅ Full flow working!

---

## Bulk Create Drivers (Python Script)

If you need to create many drivers at once, save this as `create_drivers.py`:

```python
import requests
import json

BASE_URL = "http://localhost:8000"
ADMIN_TOKEN = "your_admin_token_here"  # Get from login response

drivers_data = [
    {"name": "Alice Smith", "phone": "9800000001", "license": "DL-001", "username": "alice", "password": "Pass1!"},
    {"name": "Bob Jones", "phone": "9800000002", "license": "DL-002", "username": "bob", "password": "Pass2!"},
    {"name": "Charlie Brown", "phone": "9800000003", "license": "DL-003", "username": "charlie", "password": "Pass3!"},
]

headers = {
    "Content-Type": "application/json",
    "Authorization": f"Bearer {ADMIN_TOKEN}"
}

for driver in drivers_data:
    payload = {
        "name": driver["name"],
        "phone_number": driver["phone"],
        "license_number": driver["license"],
        "username": driver["username"],
        "password": driver["password"]
    }
    
    response = requests.post(f"{BASE_URL}/api/drivers/", json=payload, headers=headers)
    
    if response.status_code == 201:
        print(f"✅ Created driver: {driver['username']}")
    else:
        print(f"❌ Failed to create {driver['username']}: {response.text}")
```

Run it:
```bash
python create_drivers.py
```

---

## Next Steps

- **Dispatch vehicles** to drivers from the dashboard
- **Monitor live location** of drivers on the map
- **Handle issue reports** from drivers in the Issues tab
- **Manage maintenance** schedules in the Maintenance tab

For more details, see **README.md**.