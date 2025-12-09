import { City } from '@/constants/Cities';
import { useEffect, useMemo, useRef } from 'react';
import { Animated, Dimensions, Easing, StyleSheet, View } from 'react-native';
import Svg, { Circle, Defs, Ellipse, G, RadialGradient, Stop } from 'react-native-svg';

const { width, height } = Dimensions.get('window');
const GLOBE_SIZE = Math.min(width * 0.7, 260);

interface GlobeProps {
    targetCity?: City;
    autoRotate?: boolean;
}

export default function Globe({ targetCity, autoRotate = true }: GlobeProps) {
    const rotation = useRef(new Animated.Value(0)).current;

    const stars = useMemo(() =>
        Array.from({ length: 60 }).map(() => ({
            left: Math.random() * 100,
            top: Math.random() * 100,
            size: Math.random() * 1.2 + 0.3,
            opacity: Math.random() * 0.4 + 0.1,
        })),
        []);

    useEffect(() => {
        if (autoRotate) {
            Animated.loop(
                Animated.timing(rotation, {
                    toValue: 360,
                    duration: 80000,
                    easing: Easing.linear,
                    useNativeDriver: true,
                })
            ).start();
        }
    }, [autoRotate]);

    const spin = rotation.interpolate({
        inputRange: [0, 360],
        outputRange: ['0deg', '360deg'],
    });

    return (
        <View style={styles.container}>
            {/* Stars */}
            <View style={styles.starsContainer}>
                {stars.map((star, i) => (
                    <View
                        key={i}
                        style={[
                            styles.star,
                            {
                                left: `${star.left}%`,
                                top: `${star.top}%`,
                                width: star.size,
                                height: star.size,
                                opacity: star.opacity,
                            },
                        ]}
                    />
                ))}
            </View>

            {/* Globe */}
            <Animated.View
                style={[
                    styles.globeContainer,
                    { transform: [{ rotate: spin }] },
                ]}
            >
                <Svg width={GLOBE_SIZE} height={GLOBE_SIZE} viewBox="0 0 200 200">
                    <Defs>
                        <RadialGradient id="oceanGradient" cx="45%" cy="40%" r="55%">
                            <Stop offset="0%" stopColor="#4b5563" stopOpacity="1" />
                            <Stop offset="100%" stopColor="#1f2937" stopOpacity="1" />
                        </RadialGradient>
                    </Defs>

                    {/* Main globe - grey */}
                    <Circle cx="100" cy="100" r="80" fill="url(#oceanGradient)" />

                    {/* Continents - orange tinted */}
                    <G opacity="0.7">
                        <Ellipse cx="48" cy="62" rx="24" ry="18" fill="#f97316" />
                        <Ellipse cx="38" cy="78" rx="12" ry="10" fill="#f97316" />
                        <Ellipse cx="58" cy="120" rx="12" ry="24" fill="#f97316" />
                        <Ellipse cx="112" cy="72" rx="10" ry="16" fill="#f97316" />
                        <Ellipse cx="115" cy="105" rx="14" ry="22" fill="#f97316" />
                        <Ellipse cx="148" cy="58" rx="26" ry="24" fill="#f97316" />
                        <Ellipse cx="160" cy="80" rx="14" ry="12" fill="#f97316" />
                        <Ellipse cx="155" cy="128" rx="16" ry="10" fill="#f97316" />
                    </G>

                    {/* Grid - subtle */}
                    <G stroke="rgba(255,255,255,0.08)" strokeWidth="0.4" fill="none">
                        <Ellipse cx="100" cy="100" rx="80" ry="22" />
                        <Ellipse cx="100" cy="100" rx="80" ry="50" />
                        <Ellipse cx="100" cy="100" rx="22" ry="80" />
                        <Ellipse cx="100" cy="100" rx="50" ry="80" />
                    </G>

                    {/* City marker */}
                    {targetCity && (
                        <Circle
                            cx={100 + (targetCity.longitude / 180) * 42}
                            cy={100 - (targetCity.latitude / 90) * 42}
                            r="5"
                            fill="#fff"
                        />
                    )}
                </Svg>
            </Animated.View>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#121214',
        justifyContent: 'center',
        alignItems: 'center',
    },
    starsContainer: {
        ...StyleSheet.absoluteFillObject,
    },
    star: {
        position: 'absolute',
        backgroundColor: '#fff',
        borderRadius: 4,
    },
    globeContainer: {
        justifyContent: 'center',
        alignItems: 'center',
    },
});
