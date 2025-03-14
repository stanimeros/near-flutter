#!/usr/bin/env python3
import requests
import json
import random
import time
import uuid
from pprint import pprint
from datetime import datetime

# Base URL for the API
BASE_URL = "https://snf-78417.ok-kno.grnetcloud.net/api"

# Thessaloniki center coordinates
THESSALONIKI_CENTER = {
    "longitude": 22.9444,
    "latitude": 40.6401
}

EVOSMOS_POINT = {
    "longitude": 22.91143192126404,  # Guaranteed point within ΕΥΟΣΜΟΥ
    "latitude": 40.67714716078126
}
   
KALAMARIA_POINT = {
    "longitude": 22.958349035008524,  # Guaranteed point within ΚΑΛΑΜΑΡΙΑΣ
    "latitude": 40.57642150775372
}

# Points outside city boundaries
OUTSIDE_POINT_1 = {
    "longitude": 22.5,  # Point far west of Thessaloniki
    "latitude": 40.3
}

OUTSIDE_POINT_2 = {
    "longitude": 23.2,  # Point far east of Thessaloniki
    "latitude": 40.8
}

# Generate random coordinates near Thessaloniki
def random_location_near_thessaloniki():
    # Random offset within ~5km
    lon_offset = random.uniform(-0.05, 0.05)
    lat_offset = random.uniform(-0.05, 0.05)
    
    return {
        "longitude": THESSALONIKI_CENTER["longitude"] + lon_offset,
        "latitude": THESSALONIKI_CENTER["latitude"] + lat_offset
    }

# Generate a random bounding box near Thessaloniki
def random_bbox_near_thessaloniki():
    center = random_location_near_thessaloniki()
    
    # Create a small bounding box (about 1-2km)
    size = random.uniform(0.01, 0.02)
    
    return {
        "minLon": center["longitude"] - size,
        "minLat": center["latitude"] - size,
        "maxLon": center["longitude"] + size,
        "maxLat": center["latitude"] + size
    }

# Test the /api/points endpoint
def test_points_api():
    print("\n=== Testing /api/points endpoint ===")
    
    # Generate random bounding box
    bbox = random_bbox_near_thessaloniki()
    print(f"Using bounding box: {bbox}")
    
    # Make the request
    response = requests.get(
        f"{BASE_URL}/points",
        params=bbox,
    )
    
    # Print results
    print(f"Status code: {response.status_code}")
    if response.status_code == 200:
        data = response.json()
        print(f"Found {data['count']} points")
        if data['count'] > 0:
            print("Sample point:", data['points'][0])
    else:
        print("Error:", response.text)
    
    return response.status_code == 200

# Test the /api/cities endpoint
def test_cities_api():
    print("\n=== Testing /api/cities endpoint ===")
    
    # Generate random bounding box
    bbox = random_bbox_near_thessaloniki()
    print(f"Using bounding box: {bbox}")
    
    # Make the request
    response = requests.get(
        f"{BASE_URL}/cities",
        params=bbox,
    )
    
    # Print results
    print(f"Status code: {response.status_code}")
    if response.status_code == 200:
        data = response.json()
        print(f"Found {data['count']} cities")
        if data['count'] > 0:
            print(f"Cities found: {[city['name'] for city in data['cities']]}")
            print("Sample city geometry type:", json.loads(data['cities'][0]['geometry'])['type'])
    else:
        print("Error:", response.text)
    
    return response.status_code == 200

# Test the /api/clusters endpoint
def test_clusters_api():
    print("\n=== Testing /api/clusters endpoint ===")
    
    # Test 1: Points within city boundaries (Evosmos and Kalamaria)
    print("\n--- Test 1: Points within city boundaries ---")
    params = {
        "lon1": EVOSMOS_POINT["longitude"],
        "lat1": EVOSMOS_POINT["latitude"],
        "lon2": KALAMARIA_POINT["longitude"],
        "lat2": KALAMARIA_POINT["latitude"]
    }
    
    print(f"Using a Kalamaria point and an Evosmos point:")
    print(f"Point 1: {params['lon1']}, {params['lat1']}")
    print(f"Point 2: {params['lon2']}, {params['lat2']}")
    
    # Make the request
    response = requests.get(
        f"{BASE_URL}/clusters",
        params=params,
    )
    
    # Print results
    print(f"Status code: {response.status_code}")
    if response.status_code == 200:
        data = response.json()
        print(f"Found {data['count']} clusters")
        if 'cities' in data and len(data['cities']) > 0:
            print(f"Cities found: {[city['name'] for city in data['cities']]}")
            
            # Verify we got exactly 2 cities (one for each point)
            if len(data['cities']) == 2:
                print("✅ Test passed: Found exactly 2 cities (one for each point)")
            else:
                print(f"❌ Test failed: Expected 2 cities, got {len(data['cities'])}")
            
            # Print sample clusters from each city if available
            for city in data['cities']:
                if len(city['clusters']) > 0:
                    print(f"Sample cluster from {city['name']}:", city['clusters'][0])
    else:
        print("Error:", response.text)
    
    # Test 2: Points outside city boundaries
    print("\n--- Test 2: Points outside city boundaries ---")
    params = {
        "lon1": OUTSIDE_POINT_1["longitude"],
        "lat1": OUTSIDE_POINT_1["latitude"],
        "lon2": OUTSIDE_POINT_2["longitude"],
        "lat2": OUTSIDE_POINT_2["latitude"]
    }
    
    print(f"Using points outside city boundaries:")
    print(f"Point 1: {params['lon1']}, {params['lat1']}")
    print(f"Point 2: {params['lon2']}, {params['lat2']}")
    
    # Make the request
    response = requests.get(
        f"{BASE_URL}/clusters",
        params=params,
    )
    
    # Print results
    print(f"Status code: {response.status_code}")
    if response.status_code == 200:
        data = response.json()
        print(f"Found {data['count']} clusters")
        if 'cities' in data and len(data['cities']) > 0:
            print(f"Cities found: {[city['name'] for city in data['cities']]}")
            
            # Verify we got at most 2 cities (one for each point)
            if len(data['cities']) <= 2:
                print(f"✅ Test passed: Found {len(data['cities'])} cities (at most one for each point)")
            else:
                print(f"❌ Test failed: Expected at most 2 cities, got {len(data['cities'])}")
            
            # Print sample clusters from each city if available
            for city in data['cities']:
                if len(city['clusters']) > 0:
                    print(f"Sample cluster from {city['name']}:", city['clusters'][0])
        else:
            print("No cities found, which is acceptable for points far outside city boundaries")
    else:
        print("Error:", response.text)
    
    # Test 3: One point inside, one point outside
    print("\n--- Test 3: One point inside, one point outside ---")
    params = {
        "lon1": EVOSMOS_POINT["longitude"],
        "lat1": EVOSMOS_POINT["latitude"],
        "lon2": OUTSIDE_POINT_1["longitude"],
        "lat2": OUTSIDE_POINT_1["latitude"]
    }
    
    print(f"Using one point inside a city and one outside:")
    print(f"Point 1 (inside): {params['lon1']}, {params['lat1']}")
    print(f"Point 2 (outside): {params['lon2']}, {params['lat2']}")
    
    # Make the request
    response = requests.get(
        f"{BASE_URL}/clusters",
        params=params,
    )
    
    # Print results
    print(f"Status code: {response.status_code}")
    if response.status_code == 200:
        data = response.json()
        print(f"Found {data['count']} clusters")
        if 'cities' in data and len(data['cities']) > 0:
            print(f"Cities found: {[city['name'] for city in data['cities']]}")
            
            # Verify we got at most 2 cities (one for each point)
            if len(data['cities']) <= 2:
                print(f"✅ Test passed: Found {len(data['cities'])} cities (at most one for each point)")
            else:
                print(f"❌ Test failed: Expected at most 2 cities, got {len(data['cities'])}")
            
            # Print sample clusters from each city if available
            for city in data['cities']:
                if len(city['clusters']) > 0:
                    print(f"Sample cluster from {city['name']}:", city['clusters'][0])
    else:
        print("Error:", response.text)
    
    # Test 4: Same point twice (should return only one city)
    print("\n--- Test 4: Same point twice ---")
    params = {
        "lon1": EVOSMOS_POINT["longitude"],
        "lat1": EVOSMOS_POINT["latitude"],
        "lon2": EVOSMOS_POINT["longitude"],
        "lat2": EVOSMOS_POINT["latitude"]
    }
    
    print(f"Using the same point twice:")
    print(f"Point 1 & 2: {params['lon1']}, {params['lat1']}")
    
    # Make the request
    response = requests.get(
        f"{BASE_URL}/clusters",
        params=params,
    )
    
    # Print results
    print(f"Status code: {response.status_code}")
    if response.status_code == 200:
        data = response.json()
        print(f"Found {data['count']} clusters")
        if 'cities' in data and len(data['cities']) > 0:
            print(f"Cities found: {[city['name'] for city in data['cities']]}")
            
            # Verify we got exactly 1 city (since both points are the same)
            if len(data['cities']) == 1:
                print("✅ Test passed: Found exactly 1 city (since both points are the same)")
            else:
                print(f"❌ Test failed: Expected 1 city, got {len(data['cities'])}")
            
            # Print sample clusters from the city if available
            if len(data['cities'][0]['clusters']) > 0:
                print(f"Sample cluster from {data['cities'][0]['name']}:", data['cities'][0]['clusters'][0])
    else:
        print("Error:", response.text)
    
    return response.status_code == 200

# Test the meetings API
def test_meetings_api():
    print("\n=== Testing Meetings API ===")
    
    # Step 1: Create a meeting
    print("\n--- Creating a meeting ---")
    location = {
        "longitude": THESSALONIKI_CENTER["longitude"],
        "latitude": THESSALONIKI_CENTER["latitude"],
        "datetime": datetime.now().isoformat()
    }
    response = requests.post(
        f"{BASE_URL}/meetings",
        json=location,
        headers={"Content-Type": "application/json"}
    )
    
    if response.status_code != 200:
        print(f"Failed to create meeting: {response.text}")
        return False
    
    meeting_data = response.json()
    token = meeting_data['meeting']['token']
    print(f"Meeting created with token: {token}")
    
    # Step 2: Suggest a location
    print("\n--- Suggesting a location ---")
    location = random_location_near_thessaloniki()
    # Add datetime to the location
    location["datetime"] = datetime.now().isoformat()
    print(f"Suggesting location: {location}")
    
    response = requests.post(
        f"{BASE_URL}/meetings/{token}/suggest",
        json=location,
        headers={"Content-Type": "application/json"}
    )
    
    if response.status_code != 200:
        print(f"Failed to suggest location: {response.text}")
        return False
    
    print("Location suggested successfully")
    pprint(response.json()['meeting'])
    
    # Step 3: Get meeting details
    print("\n--- Getting meeting details ---")
    response = requests.get(
        f"{BASE_URL}/meetings/{token}",
    )
    
    if response.status_code != 200:
        print(f"Failed to get meeting: {response.text}")
        return False
    
    print("Meeting details retrieved successfully")
    pprint(response.json()['meeting'])
    
    # Step 4: Update the location (using suggest again)
    print("\n--- Updating the location ---")
    new_location = random_location_near_thessaloniki()
    # Add datetime to the location
    new_location["datetime"] = datetime.now().isoformat()
    print(f"New location: {new_location}")
    
    response = requests.post(
        f"{BASE_URL}/meetings/{token}/suggest",
        json=new_location,
        headers={"Content-Type": "application/json"}
    )
    
    if response.status_code != 200:
        print(f"Failed to update location: {response.text}")
        return False
    
    print("Location updated successfully")
    pprint(response.json()['meeting'])
    
    # Step 5: Accept the meeting
    print("\n--- Accepting the meeting ---")
    response = requests.post(
        f"{BASE_URL}/meetings/{token}/accept",
    )
    
    if response.status_code != 200:
        print(f"Failed to accept meeting: {response.text}")
        return False
    
    print("Meeting accepted successfully")
    pprint(response.json()['meeting'])
    
    # Step 6: Try to reject the meeting (should work even after accepting)
    print("\n--- Rejecting the meeting ---")
    response = requests.post(
        f"{BASE_URL}/meetings/{token}/reject",
    )
    
    if response.status_code != 200:
        print(f"Failed to reject meeting: {response.text}")
        return False
    
    print("Meeting rejected successfully")
    pprint(response.json()['meeting'])
    
    # Step 7: Test with invalid token
    print("\n--- Testing with invalid token ---")
    invalid_token = str(uuid.uuid4())
    response = requests.get(
        f"{BASE_URL}/meetings/{invalid_token}",
    )
    
    if response.status_code == 404:
        print("Invalid token test passed (404 Not Found)")
    else:
        print(f"Invalid token test failed: {response.status_code} - {response.text}")
    
    return True

# Test error handling
def test_error_handling():
    print("\n=== Testing Error Handling ===")
    
    # Test invalid coordinates
    print("\n--- Testing invalid coordinates ---")
    params = {
        "lon1": 200,  # Invalid longitude
        "lat1": 40.6401,
        "lon2": 22.9444,
        "lat2": 40.6401
    }
    
    response = requests.get(
        f"{BASE_URL}/clusters",
        params=params,
    )
    
    if response.status_code == 400:
        print("Invalid coordinates test passed (400 Bad Request)")
        print(f"Error message: {response.json().get('error', 'No error message')}")
    else:
        print(f"Invalid coordinates test failed: {response.status_code} - {response.text}")
    
    # Test missing parameters
    print("\n--- Testing missing parameters ---")
    params = {
        "lon1": 22.9444,
        "lat1": 40.6401
        # Missing lon2 and lat2
    }
    
    response = requests.get(
        f"{BASE_URL}/clusters",
        params=params,
    )
    
    if response.status_code == 400:
        print("Missing parameters test passed (400 Bad Request)")
        print(f"Error message: {response.json().get('error', 'No error message')}")
    else:
        print(f"Missing parameters test failed: {response.status_code} - {response.text}")
    
    return True

# Main function to run all tests
def main():
    print("Starting API tests...")
    
    # Run all tests
    points_success = test_points_api()
    cities_success = test_cities_api()
    clusters_success = test_clusters_api()
    meetings_success = test_meetings_api()
    error_handling_success = test_error_handling()
    
    # Print summary
    print("\n=== Test Summary ===")
    print(f"Points API: {'SUCCESS' if points_success else 'FAILED'}")
    print(f"Cities API: {'SUCCESS' if cities_success else 'FAILED'}")
    print(f"Clusters API: {'SUCCESS' if clusters_success else 'FAILED'}")
    print(f"Meetings API: {'SUCCESS' if meetings_success else 'FAILED'}")
    print(f"Error Handling: {'SUCCESS' if error_handling_success else 'FAILED'}")
    
    # Overall result
    if all([points_success, cities_success, clusters_success, meetings_success, error_handling_success]):
        print("\nAll tests PASSED!")
    else:
        print("\nSome tests FAILED!")

if __name__ == "__main__":
    main()
