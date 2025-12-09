import { City, DEFAULT_CITIES } from '@/constants/Cities';
import AsyncStorage from '@react-native-async-storage/async-storage';

const STORAGE_KEYS = {
    BOOKMARKED_CITIES: '@vihari/bookmarked_cities',
    ALARMS: '@vihari/alarms',
    SETTINGS: '@vihari/settings',
};

export interface Alarm {
    id: string;
    time: string; // HH:mm format
    timezone: string;
    label: string;
    enabled: boolean;
    days: number[]; // 0-6 for Sun-Sat
}

export interface Settings {
    temperatureUnit: 'celsius' | 'fahrenheit';
    windSpeedUnit: 'kmh' | 'mph' | 'ms';
    timeFormat: '12h' | '24h';
    notificationsEnabled: boolean;
}

const DEFAULT_SETTINGS: Settings = {
    temperatureUnit: 'celsius',
    windSpeedUnit: 'kmh',
    timeFormat: '12h',
    notificationsEnabled: true,
};

// Cities
export async function getBookmarkedCities(): Promise<City[]> {
    try {
        const data = await AsyncStorage.getItem(STORAGE_KEYS.BOOKMARKED_CITIES);
        if (data) {
            return JSON.parse(data);
        }
        // Return default cities on first launch
        await saveBookmarkedCities(DEFAULT_CITIES.slice(0, 3));
        return DEFAULT_CITIES.slice(0, 3);
    } catch (error) {
        console.error('Error loading cities:', error);
        return DEFAULT_CITIES.slice(0, 3);
    }
}

export async function saveBookmarkedCities(cities: City[]): Promise<void> {
    try {
        await AsyncStorage.setItem(STORAGE_KEYS.BOOKMARKED_CITIES, JSON.stringify(cities));
    } catch (error) {
        console.error('Error saving cities:', error);
    }
}

export async function addCity(city: City): Promise<City[]> {
    const cities = await getBookmarkedCities();
    const exists = cities.find((c) => c.id === city.id);
    if (!exists) {
        cities.push(city);
        await saveBookmarkedCities(cities);
    }
    return cities;
}

export async function removeCity(cityId: string): Promise<City[]> {
    const cities = await getBookmarkedCities();
    const filtered = cities.filter((c) => c.id !== cityId);
    await saveBookmarkedCities(filtered);
    return filtered;
}

// Alarms
export async function getAlarms(): Promise<Alarm[]> {
    try {
        const data = await AsyncStorage.getItem(STORAGE_KEYS.ALARMS);
        return data ? JSON.parse(data) : [];
    } catch (error) {
        console.error('Error loading alarms:', error);
        return [];
    }
}

export async function saveAlarms(alarms: Alarm[]): Promise<void> {
    try {
        await AsyncStorage.setItem(STORAGE_KEYS.ALARMS, JSON.stringify(alarms));
    } catch (error) {
        console.error('Error saving alarms:', error);
    }
}

export async function addAlarm(alarm: Alarm): Promise<Alarm[]> {
    const alarms = await getAlarms();
    alarms.push(alarm);
    await saveAlarms(alarms);
    return alarms;
}

export async function updateAlarm(alarm: Alarm): Promise<Alarm[]> {
    const alarms = await getAlarms();
    const index = alarms.findIndex((a) => a.id === alarm.id);
    if (index !== -1) {
        alarms[index] = alarm;
        await saveAlarms(alarms);
    }
    return alarms;
}

export async function deleteAlarm(alarmId: string): Promise<Alarm[]> {
    const alarms = await getAlarms();
    const filtered = alarms.filter((a) => a.id !== alarmId);
    await saveAlarms(filtered);
    return filtered;
}

// Settings
export async function getSettings(): Promise<Settings> {
    try {
        const data = await AsyncStorage.getItem(STORAGE_KEYS.SETTINGS);
        return data ? { ...DEFAULT_SETTINGS, ...JSON.parse(data) } : DEFAULT_SETTINGS;
    } catch (error) {
        console.error('Error loading settings:', error);
        return DEFAULT_SETTINGS;
    }
}

export async function saveSettings(settings: Settings): Promise<void> {
    try {
        await AsyncStorage.setItem(STORAGE_KEYS.SETTINGS, JSON.stringify(settings));
    } catch (error) {
        console.error('Error saving settings:', error);
    }
}

export async function updateSetting<K extends keyof Settings>(
    key: K,
    value: Settings[K]
): Promise<Settings> {
    const settings = await getSettings();
    settings[key] = value;
    await saveSettings(settings);
    return settings;
}
