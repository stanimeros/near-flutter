#!/usr/bin/env python3
import requests
import json
import random
import time
import uuid
from pprint import pprint

# Base URL for the API
BASE_URL = "https://snf-78417.ok-kno.grnetcloud.net/api"

# Thessaloniki center coordinates
THESSALONIKI_CENTER = {
    "longitude": 22.9444,
    "latitude": 40.6401
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

# Test the /api/clusters endpoint
def test_clusters_api():
    print("\n=== Testing /api/clusters endpoint ===")
    
    # Generate two random locations
    loc1 = random_location_near_thessaloniki()
    loc2 = random_location_near_thessaloniki()
    
    params = {
        "lon1": loc1["longitude"],
        "lat1": loc1["latitude"],
        "lon2": loc2["longitude"],
        "lat2": loc2["latitude"]
    }
    
    print(f"Using locations: {params}")
    
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
            
            # Print sample clusters from first city if available
            first_city = data['cities'][0]
            if len(first_city['clusters']) > 0:
                print(f"Sample cluster from {first_city['name']}:", first_city['clusters'][0])
    else:
        print("Error:", response.text)
    
    return response.status_code == 200

# Test the meetings API
def test_meetings_api():
    print("\n=== Testing Meetings API ===")
    
    # Step 1: Create a meeting
    print("\n--- Creating a meeting ---")
    response = requests.post(
        f"{BASE_URL}/meetings",
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
    print(f"Suggesting location: {location}")
    
    response = requests.post(
        f"{BASE_URL}/meetings/{token}/suggest",
        json=location,
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
    
    # Step 4: Re-suggest a location
    print("\n--- Re-suggesting a location ---")
    new_location = random_location_near_thessaloniki()
    print(f"Re-suggesting location: {new_location}")
    
    response = requests.post(
        f"{BASE_URL}/meetings/{token}/resuggest",
        json=new_location,
    )
    
    if response.status_code != 200:
        print(f"Failed to re-suggest location: {response.text}")
        return False
    
    print("Location re-suggested successfully")
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
    
    # Step 7: Cancel the meeting
    print("\n--- Cancelling the meeting ---")
    response = requests.post(
        f"{BASE_URL}/meetings/{token}/cancel",
    )
    
    if response.status_code != 200:
        print(f"Failed to cancel meeting: {response.text}")
        return False
    
    print("Meeting cancelled successfully")
    pprint(response.json()['meeting'])
    
    # Step 8: Test with invalid token
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
    clusters_success = test_clusters_api()
    meetings_success = test_meetings_api()
    error_handling_success = test_error_handling()
    
    # Print summary
    print("\n=== Test Summary ===")
    print(f"Points API: {'SUCCESS' if points_success else 'FAILED'}")
    print(f"Clusters API: {'SUCCESS' if clusters_success else 'FAILED'}")
    print(f"Meetings API: {'SUCCESS' if meetings_success else 'FAILED'}")
    print(f"Error Handling: {'SUCCESS' if error_handling_success else 'FAILED'}")
    
    # Overall result
    if all([points_success, clusters_success, meetings_success, error_handling_success]):
        print("\nAll tests PASSED!")
    else:
        print("\nSome tests FAILED!")

if __name__ == "__main__":
    main()
