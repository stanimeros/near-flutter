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
    min_lon = 22.94 + random.uniform(-0.005, 0.005)
    min_lat = 40.62 + random.uniform(-0.005, 0.005)
    max_lon = min_lon + random.uniform(0.005, 0.01)
    max_lat = min_lat + random.uniform(0.005, 0.01)
    return min_lon, min_lat, max_lon, max_lat

# Function to make an API request
def fetch_url(endpoint):
    start_time = time.time()
    try:
        response = requests.get(endpoint, timeout=5)
        elapsed_time = time.time() - start_time
        
        if response.status_code == 200:
            data = response.json()
            source = data.get('source', 'unknown')
            return {
                'status_code': response.status_code,
                'elapsed_time': round(elapsed_time, 4),
                'source': source,
                'clusters_count': len(data.get('clusters', []))
            }
        else:
            print(f"\nBad request ({response.status_code}): {endpoint}")
            print(f"Response: {response.text}")
            return {
                'status_code': response.status_code,
                'elapsed_time': round(elapsed_time, 4),
                'source': 'error',
                'clusters_count': 0
            }
    except requests.exceptions.RequestException as e:
        print(f"\nError fetching URL: {e}")
        print(f"URL: {endpoint}")
        return {
            'status_code': 'Error',
            'elapsed_time': 0,
            'source': 'error',
            'clusters_count': 0
        }

# Function to test API with random parameters
async def stress_test(requests=100, concurrency=10):
    urls = []

    for _ in range(requests):
        min_lon, min_lat, max_lon, max_lat = random_coords()
        urls.append(f"{BASE_URL}cache_clusters?lon1={min_lon}&lat1={min_lat}&lon2={max_lon}&lat2={max_lat}&eps=0.0001&minPoints=3")

    print(f"\nStarting stress test with {len(urls)} requests and concurrency={concurrency}...")

    # Using ThreadPoolExecutor for parallel execution
    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        results = list(executor.map(fetch_url, urls))

    # Analyze results
    status_codes = defaultdict(int)
    source_counts = defaultdict(int)
    source_times = defaultdict(list)
    total_clusters = defaultdict(int)
    
    for result in results:
        status_codes[result['status_code']] += 1
        source = result['source']
        source_counts[source] += 1
        source_times[source].append(result['elapsed_time'])
        total_clusters[source] += result['clusters_count']

    # Calculate statistics
    success_rate = (status_codes.get(200, 0) / len(results)) * 100
    
    print("\nResults Summary:")
    print(f"Success rate (200): {success_rate:.2f}%")
    
    print("\nResponse Sources:")
    for source, count in source_counts.items():
        avg_time = sum(source_times[source]) / len(source_times[source]) if source_times[source] else 0
        avg_clusters = total_clusters[source] / count if count > 0 else 0
        print(f"- {source}: {count} requests")
        print(f"  Average time: {avg_time:.4f} seconds")
        print(f"  Average clusters: {avg_clusters:.1f}")

    print("\nStatus Codes:", dict(status_codes))

# Run the test
for i in range(100):
    asyncio.run(stress_test(requests=i + 1, concurrency=i + 1))
    print(f"Delaying for 1 second")
    time.sleep(1)