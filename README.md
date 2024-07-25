# Near

Near is a social networking application refactored to a Flutter version. Originally created as part of my undergraduate thesis at the University of Macedonia, this app focuses on privacy using the Two Hop Privacy algorithm.

## Features

- **Google Authentication:** Secure login using Google accounts.
- **Friend Requests and Chats:** Connect and communicate with friends.
- **Profile Edit:** Customize and update your profile.
- **POIs from OSM:** Automatically downloads Points of Interest (POIs) from OpenStreetMap.
- **KNN Point Selection:** Picks a K-nearest neighbors (KNN) point near you to share as your location.
- **Privacy Settings:** Configure k-anonymity settings in your profile for enhanced privacy.
- **Geo Database:** Uses [`sqlite3_flutter_libs`](https://pub.dev/packages/sqlite3_flutter_libs) and [`flutter_geopackage`](https://pub.dev/packages/flutter_geopackage) to create spatial tables in SQLite and perform spatial queries. The database loads very fast, with query times between 5-50 ms.



## Installation and Usage

### Prerequisites

- Minimum SDK for Android: 26
- Minimum iOS version: 13

### Steps

1. Clone the repository:
   ```sh
   git clone https://github.com/stanimeros/near-flutter.git
2. Navigate to the project directory:
    ```sh
    cd near-flutter
3. Install dependencies:
    ```sh
    flutter pub get
4. Run the application:
    ```sh
    flutter run
<br>
<img src="https://github.com/user-attachments/assets/2b8c550a-be09-4a96-91c1-52b4168d9b97" width="33%"></img> 
<img src="https://github.com/user-attachments/assets/35755895-ab03-45f2-a54a-59b9c7c16008" width="33%"></img> 
<img src="https://github.com/user-attachments/assets/c87320c2-f9bc-487e-9d4d-754f9660cb14" width="33%"></img> 
<img src="https://github.com/user-attachments/assets/21ba1ad7-be7f-4e86-91fd-e922298d0ff5" width="33%"></img> 
<img src="https://github.com/user-attachments/assets/f54bcb68-0b9c-48a3-9335-2c693042c99b" width="33%"></img> 
<img src="https://github.com/user-attachments/assets/ab625602-693a-4b09-8edf-33a55b09e8ba" width="33%"></img> 








