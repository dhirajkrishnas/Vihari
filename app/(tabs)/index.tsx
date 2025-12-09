import CityCard from '@/components/CityCard';
import Globe from '@/components/Globe';
import { City } from '@/constants/Cities';
import { getBookmarkedCities } from '@/services/storage';
import { fetchCurrentWeather, WeatherData } from '@/services/weatherApi';
import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  Animated,
  PanResponder,
  StatusBar,
  StyleSheet,
  TouchableOpacity,
  View
} from 'react-native';

const SWIPE_THRESHOLD = 50;

export default function HomeScreen() {
  const [cities, setCities] = useState<City[]>([]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [weatherData, setWeatherData] = useState<Record<string, WeatherData>>({});
  const translateY = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    loadCities();
  }, []);

  const loadCities = async () => {
    const bookmarked = await getBookmarkedCities();
    setCities(bookmarked);
    bookmarked.forEach(fetchWeatherForCity);
  };

  const fetchWeatherForCity = async (city: City) => {
    try {
      const weather = await fetchCurrentWeather(city.latitude, city.longitude);
      setWeatherData(prev => ({ ...prev, [city.id]: weather }));
    } catch (error) {
      console.error(`Error fetching weather for ${city.name}:`, error);
    }
  };

  const goToCity = useCallback((index: number) => {
    if (index >= 0 && index < cities.length) {
      setCurrentIndex(index);
    }
  }, [cities.length]);

  const handleSwipe = useCallback((direction: 'up' | 'down') => {
    if (direction === 'up' && currentIndex < cities.length - 1) {
      goToCity(currentIndex + 1);
    } else if (direction === 'down' && currentIndex > 0) {
      goToCity(currentIndex - 1);
    }
  }, [currentIndex, cities.length, goToCity]);

  const panResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponder: (_, gestureState) => {
        return Math.abs(gestureState.dy) > 10;
      },
      onPanResponderMove: (_, gestureState) => {
        translateY.setValue(gestureState.dy * 0.4);
      },
      onPanResponderRelease: (_, gestureState) => {
        if (gestureState.dy < -SWIPE_THRESHOLD) {
          handleSwipe('up');
        } else if (gestureState.dy > SWIPE_THRESHOLD) {
          handleSwipe('down');
        }
        Animated.spring(translateY, {
          toValue: 0,
          useNativeDriver: true,
          tension: 60,
          friction: 12,
        }).start();
      },
    })
  ).current;

  const handleCityPress = (city: City) => {
    router.push(`/city/${city.id}`);
  };

  const handleAddLocation = () => {
    console.log('Add location');
  };

  const currentCity = cities[currentIndex];

  return (
    <View style={styles.container}>
      <StatusBar barStyle="light-content" />

      {/* Globe */}
      <View style={styles.globeContainer}>
        <Globe targetCity={currentCity} autoRotate={!currentCity} />
      </View>

      {/* City Cards */}
      <View style={styles.cardsContainer} {...panResponder.panHandlers}>
        <Animated.View
          style={[
            styles.cardWrapper,
            { transform: [{ translateY }] },
          ]}
        >
          {currentCity && (
            <CityCard
              city={currentCity}
              weather={weatherData[currentCity.id]}
              onPress={() => handleCityPress(currentCity)}
              isActive={true}
            />
          )}
        </Animated.View>

        {/* Indicators */}
        <View style={styles.indicators}>
          {cities.map((_, index) => (
            <View
              key={index}
              style={[
                styles.indicator,
                index === currentIndex && styles.activeIndicator,
              ]}
            />
          ))}
        </View>
      </View>

      {/* Add Button */}
      <View style={styles.addButtonContainer}>
        <TouchableOpacity
          style={styles.addButton}
          onPress={handleAddLocation}
          activeOpacity={0.8}
        >
          <Ionicons name="add" size={24} color="#fff" />
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#121214',
  },
  globeContainer: {
    ...StyleSheet.absoluteFillObject,
  },
  cardsContainer: {
    position: 'absolute',
    bottom: 150,
    left: 0,
    right: 0,
    alignItems: 'center',
  },
  cardWrapper: {
    marginBottom: 16,
  },
  indicators: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    gap: 6,
  },
  indicator: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
  },
  activeIndicator: {
    backgroundColor: '#f97316',
    width: 18,
  },
  addButtonContainer: {
    position: 'absolute',
    bottom: 100,
    left: 0,
    right: 0,
    alignItems: 'center',
  },
  addButton: {
    width: 52,
    height: 52,
    borderRadius: 26,
    backgroundColor: '#f97316',
    justifyContent: 'center',
    alignItems: 'center',
  },
});
