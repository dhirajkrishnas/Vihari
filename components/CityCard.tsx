import { City } from '@/constants/Cities';
import { WeatherData, getWeatherIcon } from '@/services/weatherApi';
import { formatTimeInTimezone } from '@/utils/coordinates';
import { Ionicons } from '@expo/vector-icons';
import { BlurView } from 'expo-blur';
import {
    Dimensions,
    StyleSheet,
    Text,
    TouchableOpacity,
    View,
} from 'react-native';

const { width } = Dimensions.get('window');

interface CityCardProps {
    city: City;
    weather?: WeatherData | null;
    onPress?: () => void;
    isActive?: boolean;
}

export default function CityCard({ city, weather, onPress, isActive = false }: CityCardProps) {
    const currentTime = formatTimeInTimezone(city.timezone, '12h');
    const iconName = weather
        ? getWeatherIcon(weather.weatherCode, weather.isDay)
        : 'cloud';

    return (
        <TouchableOpacity
            activeOpacity={0.9}
            onPress={onPress}
            style={styles.touchable}
        >
            <BlurView intensity={40} tint="dark" style={styles.container}>
                <View style={styles.overlay}>
                    <View style={styles.content}>
                        {/* Left side */}
                        <View style={styles.cityInfo}>
                            <Text style={styles.cityName}>{city.name}</Text>
                            <Text style={styles.countryName}>{city.country}</Text>
                            <Text style={styles.time}>{currentTime}</Text>
                        </View>

                        {/* Right side */}
                        <View style={styles.weatherInfo}>
                            <Ionicons
                                name={iconName as any}
                                size={32}
                                color="#f97316"
                            />
                            <Text style={styles.temperature}>
                                {weather ? `${Math.round(weather.temperature)}°` : '--°'}
                            </Text>
                        </View>
                    </View>

                    {/* Swipe indicator */}
                    <View style={styles.indicator}>
                        <View style={styles.swipeLine} />
                    </View>
                </View>
            </BlurView>
        </TouchableOpacity>
    );
}

const styles = StyleSheet.create({
    touchable: {
        width: width - 48,
        marginHorizontal: 24,
    },
    container: {
        borderRadius: 24,
        overflow: 'hidden',
    },
    overlay: {
        backgroundColor: 'rgba(18, 18, 20, 0.7)',
        paddingHorizontal: 24,
        paddingTop: 24,
        paddingBottom: 16,
    },
    content: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
    },
    cityInfo: {
        flex: 1,
    },
    cityName: {
        fontFamily: 'SpaceMono',
        fontSize: 24,
        fontWeight: '400',
        color: '#fff',
        letterSpacing: -0.5,
    },
    countryName: {
        fontFamily: 'SpaceMono',
        fontSize: 12,
        color: 'rgba(255, 255, 255, 0.5)',
        marginTop: 4,
    },
    time: {
        fontFamily: 'SpaceMono',
        fontSize: 14,
        color: 'rgba(255, 255, 255, 0.4)',
        marginTop: 8,
    },
    weatherInfo: {
        alignItems: 'flex-end',
    },
    temperature: {
        fontFamily: 'SpaceMono',
        fontSize: 40,
        fontWeight: '400',
        color: '#fff',
        marginTop: 4,
    },
    indicator: {
        alignItems: 'center',
        marginTop: 16,
    },
    swipeLine: {
        width: 36,
        height: 4,
        borderRadius: 2,
        backgroundColor: 'rgba(249, 115, 22, 0.5)',
    },
});
