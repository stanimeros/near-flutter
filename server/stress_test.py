import requests
import time
import random
from concurrent.futures import ThreadPoolExecutor

# Base URL
BASE_URL = "https://snf-78417.ok-kno.grnetcloud.net/api/"

# Function to generate random parameters (small bounding box variations)
def random_coords():
    min_lon = 22.851 + random.uniform(-0.0005, 0.0005)
    min_lat = 40.636 + random.uniform(-0.0005, 0.0005)
    max_lon = min_lon + random.uniform(0.0001, 0.002)
    max_lat = min_lat + random.uniform(0.0001, 0.002)
    clusters = random.randint(5, 15)  # Random number of clusters between 5 and 15
    mn_distance = random.uniform(0.0001, 0.002)  # Random minimum distance between 0.0001 and 0.002
    return min_lon, min_lat, max_lon, max_lat, clusters, mn_distance
# Function to make an API request
def fetch_url(endpoint):
    start_time = time.time()
    try:
        response = requests.get(endpoint, timeout=5)
        elapsed_time = time.time() - start_time
        if response.status_code != 200:  # Add check for non-200 responses
            print(f"\nBad request ({response.status_code}): {endpoint}")
            print(f"Response: {response.text}")
        return response.status_code, round(elapsed_time, 4)
    except requests.exceptions.RequestException as e:
        print(f"\nError fetching URL: {e}")
        print(f"URL: {endpoint}")
        return "Error", str(e)
# Function to test API with random parameters
def stress_test(n_requests=100, concurrency=10):
    urls = []

    for _ in range(n_requests):
        min_lon, min_lat, max_lon, max_lat, clusters, mn_distance = random_coords()

        # Generate endpoints with random parameters
        urls.append(f"{BASE_URL}points?minLon={min_lon}&minLat={min_lat}&maxLon={max_lon}&maxLat={max_lat}")
        urls.append(f"{BASE_URL}two-point-clusters?lon1={min_lon}&lat1={min_lat}&lon2={max_lon}&lat2={max_lat}&method=kmeans&clusters={clusters}")
        urls.append(f"{BASE_URL}two-point-clusters?lon1={min_lon}&lat1={min_lat}&lon2={max_lon}&lat2={max_lat}&method=dbscan&maxDistance={mn_distance}")

    print(f"Starting stress test with {len(urls)} requests and concurrency={concurrency}...")

    # Using ThreadPoolExecutor for parallel execution
    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        results = list(executor.map(fetch_url, urls))

    # Analyze results
    status_codes = {}
    total_time = 0
    for code, elapsed_time in results:
        if isinstance(code, int):
            status_codes[code] = status_codes.get(code, 0) + 1
        else:
            status_codes['Error'] = status_codes.get('Error', 0) + 1
        total_time += elapsed_time

    print("\n Test Results:")
    for code, count in status_codes.items():
        print(f"Status Code {code}: {count} times")
    print(f"Average response time: {total_time / len(results):.4f} seconds")

# Run the test
stress_test(n_requests=600, concurrency=20)