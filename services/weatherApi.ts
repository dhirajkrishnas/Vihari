const OPEN_METEO_BASE_URL = 'https://api.open-meteo.com/v1';

export interface WeatherData {
    temperature: number;
    feelsLike: number;
    humidity: number;
    windSpeed: number;
    windDirection: number;
    weatherCode: number;
    isDay: boolean;
    precipitation: number;
    cloudCover: number;
    pressure: number;
    visibility: number;
    uvIndex: number;
}

export interface ForecastDay {
    date: string;
    maxTemp: number;
    minTemp: number;
    weatherCode: number;
    precipitation: number;
    sunrise: string;
    sunset: string;
}

export interface HourlyForecast {
    time: string;
    temperature: number;
    weatherCode: number;
    precipitation: number;
}

export const getWeatherDescription = (code: number): string => {
    const descriptions: Record<number, string> = {
        0: 'Clear sky',
        1: 'Mainly clear',
        2: 'Partly cloudy',
        3: 'Overcast',
        45: 'Foggy',
        48: 'Depositing rime fog',
        51: 'Light drizzle',
        53: 'Moderate drizzle',
        55: 'Dense drizzle',
        61: 'Slight rain',
        63: 'Moderate rain',
        65: 'Heavy rain',
        71: 'Slight snow',
        73: 'Moderate snow',
        75: 'Heavy snow',
        77: 'Snow grains',
        80: 'Slight rain showers',
        81: 'Moderate rain showers',
        82: 'Violent rain showers',
        85: 'Slight snow showers',
        86: 'Heavy snow showers',
        95: 'Thunderstorm',
        96: 'Thunderstorm with slight hail',
        99: 'Thunderstorm with heavy hail',
    };
    return descriptions[code] || 'Unknown';
};

export const getWeatherIcon = (code: number, isDay: boolean): string => {
    if (code === 0) return isDay ? 'sunny' : 'moon';
    if (code <= 3) return isDay ? 'partly-sunny' : 'cloudy-night';
    if (code <= 48) return 'cloudy';
    if (code <= 55) return 'rainy';
    if (code <= 65) return 'rainy';
    if (code <= 77) return 'snow';
    if (code <= 82) return 'rainy';
    if (code <= 86) return 'snow';
    return 'thunderstorm';
};

export async function fetchCurrentWeather(
    latitude: number,
    longitude: number
): Promise<WeatherData> {
    const params = new URLSearchParams({
        latitude: latitude.toString(),
        longitude: longitude.toString(),
        current: [
            'temperature_2m',
            'relative_humidity_2m',
            'apparent_temperature',
            'is_day',
            'precipitation',
            'weather_code',
            'cloud_cover',
            'pressure_msl',
            'wind_speed_10m',
            'wind_direction_10m',
        ].join(','),
        timezone: 'auto',
    });

    const response = await fetch(`${OPEN_METEO_BASE_URL}/forecast?${params}`);
    const data = await response.json();

    const current = data.current;
    return {
        temperature: current.temperature_2m,
        feelsLike: current.apparent_temperature,
        humidity: current.relative_humidity_2m,
        windSpeed: current.wind_speed_10m,
        windDirection: current.wind_direction_10m,
        weatherCode: current.weather_code,
        isDay: current.is_day === 1,
        precipitation: current.precipitation,
        cloudCover: current.cloud_cover,
        pressure: current.pressure_msl,
        visibility: 10, // Not available in basic API
        uvIndex: 0, // Requires separate call
    };
}

export async function fetchForecast(
    latitude: number,
    longitude: number
): Promise<{ daily: ForecastDay[]; hourly: HourlyForecast[] }> {
    const params = new URLSearchParams({
        latitude: latitude.toString(),
        longitude: longitude.toString(),
        daily: [
            'weather_code',
            'temperature_2m_max',
            'temperature_2m_min',
            'precipitation_sum',
            'sunrise',
            'sunset',
        ].join(','),
        hourly: ['temperature_2m', 'weather_code', 'precipitation'].join(','),
        timezone: 'auto',
        forecast_days: '7',
    });

    const response = await fetch(`${OPEN_METEO_BASE_URL}/forecast?${params}`);
    const data = await response.json();

    const daily: ForecastDay[] = data.daily.time.map((date: string, i: number) => ({
        date,
        maxTemp: data.daily.temperature_2m_max[i],
        minTemp: data.daily.temperature_2m_min[i],
        weatherCode: data.daily.weather_code[i],
        precipitation: data.daily.precipitation_sum[i],
        sunrise: data.daily.sunrise[i],
        sunset: data.daily.sunset[i],
    }));

    // Get next 24 hours
    const hourly: HourlyForecast[] = data.hourly.time.slice(0, 24).map((time: string, i: number) => ({
        time,
        temperature: data.hourly.temperature_2m[i],
        weatherCode: data.hourly.weather_code[i],
        precipitation: data.hourly.precipitation[i],
    }));

    return { daily, hourly };
}
