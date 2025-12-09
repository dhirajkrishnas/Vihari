import { City, DEFAULT_CITIES } from '@/constants/Cities';
import { getBookmarkedCities } from '@/services/storage';
import {
    fetchCurrentWeather,
    fetchForecast,
    ForecastDay,
    getWeatherDescription,
    getWeatherIcon,
    HourlyForecast,
    WeatherData,
} from '@/services/weatherApi';
import { formatTimeInTimezone, getWindDirection } from '@/utils/coordinates';
import { Ionicons } from '@expo/vector-icons';
import { BlurView } from 'expo-blur';
import { Stack, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import {
    ActivityIndicator,
    Dimensions,
    ScrollView,
    StyleSheet,
    Text,
    View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

const { width } = Dimensions.get('window');

interface WeatherCardProps {
    icon: string;
    title: string;
    value: string;
    subtitle?: string;
}

function WeatherCard({ icon, title, value, subtitle }: WeatherCardProps) {
    return (
        <BlurView intensity={40} tint="dark" style={styles.weatherCard}>
            <View style={styles.cardOverlay}>
                <Ionicons name={icon as any} size={20} color="#f97316" />
                <Text style={styles.cardTitle}>{title}</Text>
                <Text style={styles.cardValue}>{value}</Text>
                {subtitle && <Text style={styles.cardSubtitle}>{subtitle}</Text>}
            </View>
        </BlurView>
    );
}

export default function CityDetailScreen() {
    const { id } = useLocalSearchParams<{ id: string }>();
    const [city, setCity] = useState<City | null>(null);
    const [weather, setWeather] = useState<WeatherData | null>(null);
    const [forecast, setForecast] = useState<{
        daily: ForecastDay[];
        hourly: HourlyForecast[];
    } | null>(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        loadCityData();
    }, [id]);

    const loadCityData = async () => {
        setLoading(true);
        try {
            const bookmarked = await getBookmarkedCities();
            const allCities = [...bookmarked, ...DEFAULT_CITIES];
            const found = allCities.find((c) => c.id === id);

            if (found) {
                setCity(found);
                const [weatherData, forecastData] = await Promise.all([
                    fetchCurrentWeather(found.latitude, found.longitude),
                    fetchForecast(found.latitude, found.longitude),
                ]);
                setWeather(weatherData);
                setForecast(forecastData);
            }
        } catch (error) {
            console.error('Error loading city data:', error);
        }
        setLoading(false);
    };

    if (loading || !city || !weather) {
        return (
            <View style={styles.loadingContainer}>
                <ActivityIndicator size="large" color="#f97316" />
            </View>
        );
    }

    const currentTime = formatTimeInTimezone(city.timezone, '12h');
    const iconName = getWeatherIcon(weather.weatherCode, weather.isDay);
    const description = getWeatherDescription(weather.weatherCode);

    return (
        <>
            <Stack.Screen
                options={{
                    headerShown: true,
                    headerTransparent: true,
                    headerTitle: '',
                    headerTintColor: '#fff',
                    headerStyle: { backgroundColor: 'transparent' },
                }}
            />
            <View style={styles.container}>
                <SafeAreaView style={styles.safeArea}>
                    <ScrollView
                        style={styles.scrollView}
                        contentContainerStyle={styles.scrollContent}
                        showsVerticalScrollIndicator={false}
                    >
                        {/* Header */}
                        <View style={styles.header}>
                            <Text style={styles.cityName}>{city.name}</Text>
                            <Text style={styles.countryName}>{city.country}</Text>
                            <Text style={styles.time}>{currentTime}</Text>
                        </View>

                        {/* Current Weather */}
                        <BlurView intensity={40} tint="dark" style={styles.currentWeather}>
                            <View style={styles.mainCardOverlay}>
                                <Ionicons name={iconName as any} size={64} color="#f97316" />
                                <Text style={styles.temperature}>{Math.round(weather.temperature)}°</Text>
                                <Text style={styles.description}>{description}</Text>
                                <Text style={styles.feelsLike}>
                                    Feels like {Math.round(weather.feelsLike)}°
                                </Text>
                            </View>
                        </BlurView>

                        {/* Weather Details Grid */}
                        <View style={styles.grid}>
                            <WeatherCard
                                icon="water-outline"
                                title="Humidity"
                                value={`${weather.humidity}%`}
                            />
                            <WeatherCard
                                icon="speedometer-outline"
                                title="Wind"
                                value={`${Math.round(weather.windSpeed)} km/h`}
                                subtitle={getWindDirection(weather.windDirection)}
                            />
                            <WeatherCard
                                icon="cloud-outline"
                                title="Clouds"
                                value={`${weather.cloudCover}%`}
                            />
                            <WeatherCard
                                icon="arrow-down-outline"
                                title="Pressure"
                                value={`${Math.round(weather.pressure)} hPa`}
                            />
                        </View>

                        {/* 7-Day Forecast */}
                        {forecast && (
                            <BlurView intensity={40} tint="dark" style={styles.forecastSection}>
                                <View style={styles.forecastOverlay}>
                                    <Text style={styles.sectionTitle}>FORECAST</Text>
                                    {forecast.daily.slice(0, 5).map((day, index) => {
                                        const date = new Date(day.date);
                                        const dayName =
                                            index === 0
                                                ? 'Today'
                                                : date.toLocaleDateString('en-US', { weekday: 'short' });
                                        const dayIcon = getWeatherIcon(day.weatherCode, true);

                                        return (
                                            <View key={day.date} style={styles.forecastRow}>
                                                <Text style={styles.forecastDay}>{dayName}</Text>
                                                <Ionicons
                                                    name={dayIcon as any}
                                                    size={20}
                                                    color="#f97316"
                                                />
                                                <Text style={styles.forecastTemp}>
                                                    {Math.round(day.maxTemp)}° / {Math.round(day.minTemp)}°
                                                </Text>
                                            </View>
                                        );
                                    })}
                                </View>
                            </BlurView>
                        )}
                    </ScrollView>
                </SafeAreaView>
            </View>
        </>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#121214',
    },
    loadingContainer: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
        backgroundColor: '#121214',
    },
    safeArea: {
        flex: 1,
    },
    scrollView: {
        flex: 1,
    },
    scrollContent: {
        paddingHorizontal: 24,
        paddingBottom: 40,
        paddingTop: 60,
    },
    header: {
        alignItems: 'center',
        marginBottom: 32,
    },
    cityName: {
        fontFamily: 'SpaceMono',
        fontSize: 28,
        color: '#fff',
    },
    countryName: {
        fontFamily: 'SpaceMono',
        fontSize: 12,
        color: 'rgba(255,255,255,0.4)',
        marginTop: 4,
    },
    time: {
        fontFamily: 'SpaceMono',
        fontSize: 12,
        color: 'rgba(255,255,255,0.3)',
        marginTop: 8,
    },
    currentWeather: {
        borderRadius: 24,
        overflow: 'hidden',
        marginBottom: 16,
    },
    mainCardOverlay: {
        backgroundColor: 'rgba(18, 18, 20, 0.7)',
        padding: 32,
        alignItems: 'center',
    },
    temperature: {
        fontFamily: 'SpaceMono',
        fontSize: 64,
        color: '#fff',
        marginTop: 8,
    },
    description: {
        fontFamily: 'SpaceMono',
        fontSize: 14,
        color: 'rgba(255,255,255,0.7)',
        marginTop: 8,
    },
    feelsLike: {
        fontFamily: 'SpaceMono',
        fontSize: 11,
        color: 'rgba(255,255,255,0.4)',
        marginTop: 8,
    },
    grid: {
        flexDirection: 'row',
        flexWrap: 'wrap',
        gap: 8,
        marginBottom: 16,
    },
    weatherCard: {
        width: (width - 48 - 8) / 2,
        borderRadius: 16,
        overflow: 'hidden',
    },
    cardOverlay: {
        backgroundColor: 'rgba(18, 18, 20, 0.7)',
        padding: 16,
        alignItems: 'center',
    },
    cardTitle: {
        fontFamily: 'SpaceMono',
        fontSize: 10,
        color: 'rgba(255,255,255,0.4)',
        marginTop: 8,
        textTransform: 'uppercase',
    },
    cardValue: {
        fontFamily: 'SpaceMono',
        fontSize: 20,
        color: '#fff',
        marginTop: 4,
    },
    cardSubtitle: {
        fontFamily: 'SpaceMono',
        fontSize: 10,
        color: 'rgba(255,255,255,0.35)',
        marginTop: 2,
    },
    forecastSection: {
        borderRadius: 20,
        overflow: 'hidden',
    },
    forecastOverlay: {
        backgroundColor: 'rgba(18, 18, 20, 0.7)',
        padding: 20,
    },
    sectionTitle: {
        fontFamily: 'SpaceMono',
        fontSize: 10,
        color: 'rgba(255,255,255,0.35)',
        letterSpacing: 1,
        marginBottom: 16,
    },
    forecastRow: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingVertical: 10,
        borderBottomWidth: 1,
        borderBottomColor: 'rgba(255,255,255,0.06)',
    },
    forecastDay: {
        fontFamily: 'SpaceMono',
        flex: 1,
        fontSize: 13,
        color: 'rgba(255,255,255,0.7)',
    },
    forecastTemp: {
        fontFamily: 'SpaceMono',
        fontSize: 13,
        color: 'rgba(255,255,255,0.5)',
        marginLeft: 16,
    },
});
