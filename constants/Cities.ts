export interface City {
    id: string;
    name: string;
    country: string;
    latitude: number;
    longitude: number;
    timezone: string;
}

export const DEFAULT_CITIES: City[] = [
    {
        id: '1',
        name: 'New York',
        country: 'USA',
        latitude: 40.7128,
        longitude: -74.006,
        timezone: 'America/New_York',
    },
    {
        id: '2',
        name: 'London',
        country: 'UK',
        latitude: 51.5074,
        longitude: -0.1278,
        timezone: 'Europe/London',
    },
    {
        id: '3',
        name: 'Tokyo',
        country: 'Japan',
        latitude: 35.6762,
        longitude: 139.6503,
        timezone: 'Asia/Tokyo',
    },
    {
        id: '4',
        name: 'Paris',
        country: 'France',
        latitude: 48.8566,
        longitude: 2.3522,
        timezone: 'Europe/Paris',
    },
    {
        id: '5',
        name: 'Sydney',
        country: 'Australia',
        latitude: -33.8688,
        longitude: 151.2093,
        timezone: 'Australia/Sydney',
    },
    {
        id: '6',
        name: 'Dubai',
        country: 'UAE',
        latitude: 25.2048,
        longitude: 55.2708,
        timezone: 'Asia/Dubai',
    },
];
