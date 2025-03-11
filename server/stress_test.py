import asyncio
import requests
import time
import random
from concurrent.futures import ThreadPoolExecutor
from collections import defaultdict

# Base URL
BASE_URL = "https://snf-78417.ok-kno.grnetcloud.net/api/"

# Function to generate random parameters (small bounding box variations)
def random_coords():
    min_lon = 22.11 + random.uniform(-0.1, 0.1)
    min_lat = 40.11 + random.uniform(-0.1, 0.1)
    max_lon = min_lon + random.uniform(0.1, 0.1)
    max_lat = min_lat + random.uniform(0.1, 0.1)
    return min_lon, min_lat, max_lon, max_lat

# Function to make an API request
def fetch_url(endpoint):
    start_time = time.time()
    try:
        response = requests.get(endpoint, timeout=30)
        elapsed_time = time.time() - start_time
        
        if response.status_code == 200:
            data = response.json()
            return {
                'status_code': response.status_code,
                'elapsed_time': round(elapsed_time, 4),
                'cached_count': data.get('cached_count', 0),
                'stored_count': data.get('stored_count', 0),
                'new_count': data.get('new_count', 0),
                'total_count': data.get('total_count', 0)
            }
        else:
            print(f"\nBad request ({response.status_code}): {endpoint}")
            print(f"Response: {response.text}")
            return {
                'status_code': response.status_code,
                'elapsed_time': round(elapsed_time, 4),
                'cached_count': 0,
                'stored_count': 0,
                'new_count': 0,
                'total_count': 0
            }
    except requests.exceptions.RequestException as e:
        print(f"\nError fetching URL: {e}")
        print(f"URL: {endpoint}")
        return {
            'status_code': 'Error',
            'elapsed_time': 0,
            'cached_count': 0,
            'stored_count': 0,
            'new_count': 0,
            'total_count': 0
        }

# Function to test API with random parameters
async def stress_test(requests=100, concurrency=10):
    urls = []

    for _ in range(requests):
        min_lon, min_lat, max_lon, max_lat = random_coords()
        urls.append(f"{BASE_URL}clusters?lon1={min_lon}&lat1={min_lat}&lon2={max_lon}&lat2={max_lat}")

    print(f"\nStarting stress test with {len(urls)} requests and concurrency={concurrency}...")

    # Using ThreadPoolExecutor for parallel execution
    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        results = list(executor.map(fetch_url, urls))

    # Analyze results
    status_codes = defaultdict(int)
    total_times = []
    total_clusters = 0
    cached_clusters = 0
    stored_clusters = 0
    new_clusters = 0
    
    for result in results:
        status_codes[result['status_code']] += 1
        if result['elapsed_time'] > 0:
            total_times.append(result['elapsed_time'])
        total_clusters += result['total_count']
        cached_clusters += result['cached_count']
        stored_clusters += result['stored_count']
        new_clusters += result['new_count']

    # Calculate statistics
    success_rate = (status_codes.get(200, 0) / len(results)) * 100
    avg_time = sum(total_times) / len(total_times) if total_times else 0
    
    print("\nResults Summary:")
    print(f"Success rate: {success_rate:.2f}%")
    print(f"Average response time: {avg_time:.4f} seconds")
    print("\nCluster Statistics:")
    print(f"Total clusters found: {total_clusters}")
    print(f"- Cached clusters: {cached_clusters}")
    print(f"- Stored clusters: {stored_clusters}")
    print(f"- New clusters: {new_clusters}")
    print("\nStatus Codes:", dict(status_codes))

# Run the test
for i in range(100):
    asyncio.run(stress_test(requests=i + 1, concurrency=i + 1))
    print(f"Delaying for 1 second")
    time.sleep(1)