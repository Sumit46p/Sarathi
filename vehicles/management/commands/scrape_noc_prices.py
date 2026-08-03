import requests
from bs4 import BeautifulSoup
from decimal import Decimal
from django.core.management.base import BaseCommand
from vehicles.models import FuelPrice

class Command(BaseCommand):
    help = 'Scrape current fuel prices from Nepal Oil Corporation (NOC)'

    def handle(self, *args, **options):
        try:
            # Scrape NOC retail price page
            self.stdout.write('Fetching NOC fuel prices from retailprice...')
            
            response = requests.get('https://noc.org.np/retailprice', timeout=10)
            response.raise_for_status()
            
            soup = BeautifulSoup(response.content, 'html.parser')
            
            # Find the pricing table
            prices = self._extract_prices_from_table(soup)
            
            if prices.get('petrol'):
                self._update_price('petrol', prices['petrol'])
                self.stdout.write(self.style.SUCCESS(f'[OK] Petrol: Rs {prices["petrol"]}/L'))
            else:
                self.stdout.write(self.style.WARNING('[WARN] Could not extract petrol price'))
            
            if prices.get('diesel'):
                self._update_price('diesel', prices['diesel'])
                self.stdout.write(self.style.SUCCESS(f'[OK] Diesel: Rs {prices["diesel"]}/L'))
            else:
                self.stdout.write(self.style.WARNING('[WARN] Could not extract diesel price'))
            
                
        except requests.RequestException as e:
            self.stdout.write(self.style.ERROR(f'[FAIL] Failed to fetch NOC page: {e}'))
        except Exception as e:
            self.stdout.write(self.style.ERROR(f'[FAIL] Error: {e}'))

    def _extract_prices_from_table(self, soup):
        """Extract prices from NOC retail price table. Returns dict with fuel types as keys."""
        prices = {}
        try:
            # Find table body
            tbody = soup.find('tbody')
            if not tbody:
                return prices
            
            # Get the first data row (most recent prices)
            row = tbody.find('tr')
            if not row:
                return prices
            
            cells = row.find_all('td')
            if len(cells) < 8:
                return prices
            
            # Column structure: date, time, petrol, diesel, kerosene, lpg, atf_dp, atf_df
            # Indices:           0     1      2       3       4         5     6        7
            
            try:
                # Extract prices from fixed column positions
                petrol = cells[2].get_text(strip=True)
                diesel = cells[3].get_text(strip=True)
                kerosene = cells[4].get_text(strip=True)
                lpg = cells[5].get_text(strip=True)
                
                # Parse each price as Decimal
                if petrol:
                    prices['petrol'] = Decimal(petrol)
                if diesel:
                    prices['diesel'] = Decimal(diesel)
                if kerosene:
                    prices['kerosene'] = Decimal(kerosene)
                if lpg:
                    prices['lpg'] = Decimal(lpg)
            
            except (ValueError, IndexError) as e:
                print(f"Error parsing prices: {e}")
            
            return prices
        except Exception as e:
            print(f"Error extracting prices from table: {e}")
            return {}

    def _update_price(self, fuel_type, price):
        """Update or create fuel price in database."""
        obj, created = FuelPrice.objects.update_or_create(
            fuel_type=fuel_type,
            defaults={'price_per_liter': price, 'source': 'NOC'}
        )
        return obj