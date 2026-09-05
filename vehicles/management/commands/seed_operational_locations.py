from django.core.management.base import BaseCommand
from django.contrib.gis.geos import Point
from vehicles.models import OperationalLocation

LOCATIONS_DATA = [
    # --- Hospitals ---
    {
        "name": "Koshi Hospital",
        "category": "hospital",
        "address": "Hospital Chowk, Biratnagar, Morang",
        "lat": 26.4525,
        "lng": 87.2797,
        "contact_phone": "021-523120",
    },
    {
        "name": "Nobel Medical College Teaching Hospital",
        "category": "hospital",
        "address": "Kanchanbari, Biratnagar, Morang",
        "lat": 26.4712,
        "lng": 87.2915,
        "contact_phone": "021-460736",
    },
    {
        "name": "Mechi Zonal Hospital",
        "category": "hospital",
        "address": "Hospital Road, Bhadrapur, Jhapa",
        "lat": 26.5442,
        "lng": 88.0894,
        "contact_phone": "023-520111",
    },
    {
        "name": "B&C Teaching Hospital",
        "category": "hospital",
        "address": "Birtamode-05, Jhapa",
        "lat": 26.6341,
        "lng": 87.9862,
        "contact_phone": "023-545555",
    },
    {
        "name": "Damak Hospital",
        "category": "hospital",
        "address": "Damak-06, Jhapa",
        "lat": 26.6612,
        "lng": 87.6975,
        "contact_phone": "023-580145",
    },
    {
        "name": "BP Koirala Institute of Health Sciences (BPKIHS)",
        "category": "hospital",
        "address": "Ghopa, Dharan, Sunsari",
        "lat": 26.8122,
        "lng": 87.2835,
        "contact_phone": "025-525555",
    },
    {
        "name": "Tribhuvan University Teaching Hospital",
        "category": "hospital",
        "address": "Maharajgunj, Kathmandu",
        "lat": 27.7348,
        "lng": 85.3308,
        "contact_phone": "01-4412404",
    },
    {
        "name": "Bir Hospital",
        "category": "hospital",
        "address": "Kanti Path, Kathmandu",
        "lat": 27.7042,
        "lng": 85.3142,
        "contact_phone": "01-4221119",
    },

    # --- Police Stations ---
    {
        "name": "Jhapa District Police Office",
        "category": "police_station",
        "address": "Bhadrapur-08, Jhapa",
        "lat": 26.5415,
        "lng": 88.0921,
        "contact_phone": "100 / 023-520199",
    },
    {
        "name": "Ward Police Office Birtamode",
        "category": "police_station",
        "address": "Mukti Chowk, Birtamode, Jhapa",
        "lat": 26.6412,
        "lng": 87.9912,
        "contact_phone": "023-540199",
    },
    {
        "name": "Area Police Office Damak",
        "category": "police_station",
        "address": "Thana Road, Damak, Jhapa",
        "lat": 26.6631,
        "lng": 87.7011,
        "contact_phone": "023-580199",
    },
    {
        "name": "Morang District Police Office",
        "category": "police_station",
        "address": "Main Road, Biratnagar, Morang",
        "lat": 26.4565,
        "lng": 87.2754,
        "contact_phone": "021-522199",
    },
    {
        "name": "Nepal Police Headquarters",
        "category": "police_station",
        "address": "Naxal, Kathmandu",
        "lat": 27.7172,
        "lng": 85.3289,
        "contact_phone": "100 / 01-4411210",
    },

    # --- Fire Stations ---
    {
        "name": "Damak Fire & Rescue Station",
        "category": "fire_station",
        "address": "Damak Municipality, Jhapa",
        "lat": 26.6589,
        "lng": 87.6987,
        "contact_phone": "101 / 023-580101",
    },
    {
        "name": "Bhadrapur Fire Station",
        "category": "fire_station",
        "address": "Bhadrapur Municipality, Jhapa",
        "lat": 26.5467,
        "lng": 88.0845,
        "contact_phone": "101 / 023-520101",
    },
    {
        "name": "Biratnagar Fire Brigade",
        "category": "fire_station",
        "address": "Biratnagar Metropolitan City, Morang",
        "lat": 26.4589,
        "lng": 87.2712,
        "contact_phone": "101 / 021-522101",
    },
    {
        "name": "Birtamode Fire & Disaster Unit",
        "category": "fire_station",
        "address": "Birtamode Municipality Office, Jhapa",
        "lat": 26.6391,
        "lng": 87.9842,
        "contact_phone": "101 / 023-541101",
    },
    {
        "name": "Kathmandu Juddha Fire Brigade",
        "category": "fire_station",
        "address": "New Road, Kathmandu",
        "lat": 27.7031,
        "lng": 85.3115,
        "contact_phone": "101 / 01-4221177",
    },

    # --- Government Offices ---
    {
        "name": "District Administration Office Jhapa (DAO)",
        "category": "government_office",
        "address": "Bhadrapur, Jhapa",
        "lat": 26.5435,
        "lng": 88.0872,
        "contact_phone": "023-520133",
    },
    {
        "name": "Biratnagar Metropolitan City Office",
        "category": "government_office",
        "address": "Main Road, Biratnagar, Morang",
        "lat": 26.4532,
        "lng": 87.2811,
        "contact_phone": "021-515155",
    },
    {
        "name": "Damak Municipality Office",
        "category": "government_office",
        "address": "Damak-05, Jhapa",
        "lat": 26.6645,
        "lng": 87.7032,
        "contact_phone": "023-580123",
    },
    {
        "name": "Inland Revenue Office Birtamode",
        "category": "government_office",
        "address": "Bhadrapur Road, Birtamode, Jhapa",
        "lat": 26.6385,
        "lng": 87.9891,
        "contact_phone": "023-542123",
    },
    {
        "name": "Singha Durbar Central Secretariat",
        "category": "government_office",
        "address": "Singha Durbar, Kathmandu",
        "lat": 27.6998,
        "lng": 85.3214,
        "contact_phone": "01-4200100",
    },

    # --- Bus Parks ---
    {
        "name": "Birtamode Central Bus Terminal",
        "category": "bus_park",
        "address": "East-West Highway, Birtamode, Jhapa",
        "lat": 26.6432,
        "lng": 87.9945,
        "contact_phone": "023-540321",
    },
    {
        "name": "Damak Main Bus Park",
        "category": "bus_park",
        "address": "Bus Park Road, Damak, Jhapa",
        "lat": 26.6601,
        "lng": 87.6952,
        "contact_phone": "023-581234",
    },
    {
        "name": "Biratnagar Central Bus Park",
        "category": "bus_park",
        "address": "Dharan Road, Biratnagar, Morang",
        "lat": 26.4678,
        "lng": 87.2789,
        "contact_phone": "021-530123",
    },
    {
        "name": "Gongabu New Bus Park",
        "category": "bus_park",
        "address": "Ring Road, Gongabu, Kathmandu",
        "lat": 27.7325,
        "lng": 85.3102,
        "contact_phone": "01-4356789",
    },

    # --- Warehouses & Fleet Depots ---
    {
        "name": "Mechi Logistics Freight Hub",
        "category": "warehouse",
        "address": "Charali Junction, Jhapa",
        "lat": 26.6512,
        "lng": 88.0512,
        "contact_phone": "023-560111",
    },
    {
        "name": "Biratnagar Inland Container Depot (ICD)",
        "category": "warehouse",
        "address": "Customs Yard, Biratnagar, Morang",
        "lat": 26.4251,
        "lng": 87.2654,
        "contact_phone": "021-470222",
    },
    {
        "name": "Koshi Central Fleet Operations Depot",
        "category": "fleet_depot",
        "address": "Itahari Chowk, Sunsari",
        "lat": 26.6651,
        "lng": 87.2784,
        "contact_phone": "025-580333",
    },
    {
        "name": "Nepal Oil Corporation Regional Depot",
        "category": "fleet_depot",
        "address": "Charali, Jhapa",
        "lat": 26.6541,
        "lng": 88.0531,
        "contact_phone": "023-560222",
    },

    # --- Registered Landmarks ---
    {
        "name": "Kakarbhitta International Border Post",
        "category": "landmark",
        "address": "Eastern Border Crossing, Jhapa",
        "lat": 26.6542,
        "lng": 88.1612,
        "contact_phone": "023-562100",
    },
    {
        "name": "Biratnagar Airport",
        "category": "landmark",
        "address": "Airport Road, Biratnagar, Morang",
        "lat": 26.4831,
        "lng": 87.2641,
        "contact_phone": "021-460182",
    },
    {
        "name": "Chandragadhi Airport",
        "category": "landmark",
        "address": "Bhadrapur, Jhapa",
        "lat": 26.5714,
        "lng": 88.0811,
        "contact_phone": "023-520188",
    },
    {
        "name": "Jamunkhadi Wetland & Reserve",
        "category": "landmark",
        "address": "Kankai Municipality, Surunga, Jhapa",
        "lat": 26.6621,
        "lng": 87.9015,
        "contact_phone": "023-550122",
    },
    {
        "name": "Kechana Kawal (Lowest Elevation Point)",
        "category": "landmark",
        "address": "Kechana, Jhapa",
        "lat": 26.3812,
        "lng": 88.0712,
        "contact_phone": "",
    },
]


class Command(BaseCommand):
    help = "Seed application database with essential Nepal operational locations (hospitals, police, fire, depots, etc.)"

    def handle(self, *args, **options):
        created_count = 0
        updated_count = 0

        for item in LOCATIONS_DATA:
            point = Point(item["lng"], item["lat"], srid=4326)
            loc, created = OperationalLocation.objects.update_or_create(
                name=item["name"],
                defaults={
                    "category": item["category"],
                    "address": item["address"],
                    "location": point,
                    "access_point": point,
                    "contact_phone": item.get("contact_phone", ""),
                    "is_active": True,
                },
            )
            if created:
                created_count += 1
            else:
                updated_count += 1

        self.stdout.write(
            self.style.SUCCESS(
                f"Successfully seeded operational locations: {created_count} created, {updated_count} updated."
            )
        )
