import { Settings, getSettings, updateSetting } from '@/services/storage';
import { Ionicons } from '@expo/vector-icons';
import { BlurView } from 'expo-blur';
import React, { useEffect, useState } from 'react';
import {
    ScrollView,
    StyleSheet,
    Switch,
    Text,
    TouchableOpacity,
    View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

interface SettingRowProps {
    icon: string;
    title: string;
    children?: React.ReactNode;
}

function SettingRow({ icon, title, children }: SettingRowProps) {
    return (
        <View style={styles.settingRow}>
            <View style={styles.settingLeft}>
                <View style={styles.settingIcon}>
                    <Ionicons name={icon as any} size={16} color="#f97316" />
                </View>
                <Text style={styles.settingTitle}>{title}</Text>
            </View>
            {children}
        </View>
    );
}

interface OptionButtonsProps {
    options: { label: string; value: string }[];
    selected: string;
    onSelect: (value: string) => void;
}

function OptionButtons({ options, selected, onSelect }: OptionButtonsProps) {
    return (
        <View style={styles.optionButtons}>
            {options.map((option) => (
                <TouchableOpacity
                    key={option.value}
                    style={[
                        styles.optionButton,
                        selected === option.value && styles.optionButtonActive,
                    ]}
                    onPress={() => onSelect(option.value)}
                >
                    <Text
                        style={[
                            styles.optionText,
                            selected === option.value && styles.optionTextActive,
                        ]}
                    >
                        {option.label}
                    </Text>
                </TouchableOpacity>
            ))}
        </View>
    );
}

export default function SettingsScreen() {
    const [settings, setSettings] = useState<Settings>({
        temperatureUnit: 'celsius',
        windSpeedUnit: 'kmh',
        timeFormat: '12h',
        notificationsEnabled: true,
    });

    useEffect(() => {
        loadSettings();
    }, []);

    const loadSettings = async () => {
        const loaded = await getSettings();
        setSettings(loaded);
    };

    const handleSettingChange = async <K extends keyof Settings>(
        key: K,
        value: Settings[K]
    ) => {
        const updated = await updateSetting(key, value);
        setSettings(updated);
    };

    return (
        <View style={styles.container}>
            <SafeAreaView style={styles.safeArea}>
                <View style={styles.header}>
                    <Text style={styles.title}>Settings</Text>
                    <Text style={styles.subtitle}>Preferences</Text>
                </View>

                <ScrollView
                    style={styles.scrollView}
                    contentContainerStyle={styles.scrollContent}
                    showsVerticalScrollIndicator={false}
                >
                    {/* Units */}
                    <BlurView intensity={40} tint="dark" style={styles.section}>
                        <View style={styles.sectionOverlay}>
                            <Text style={styles.sectionTitle}>UNITS</Text>

                            <SettingRow icon="thermometer-outline" title="Temperature">
                                <OptionButtons
                                    options={[
                                        { label: '°C', value: 'celsius' },
                                        { label: '°F', value: 'fahrenheit' },
                                    ]}
                                    selected={settings.temperatureUnit}
                                    onSelect={(value) =>
                                        handleSettingChange('temperatureUnit', value as 'celsius' | 'fahrenheit')
                                    }
                                />
                            </SettingRow>

                            <View style={styles.divider} />

                            <SettingRow icon="speedometer-outline" title="Wind">
                                <OptionButtons
                                    options={[
                                        { label: 'km/h', value: 'kmh' },
                                        { label: 'mph', value: 'mph' },
                                    ]}
                                    selected={settings.windSpeedUnit}
                                    onSelect={(value) =>
                                        handleSettingChange('windSpeedUnit', value as 'kmh' | 'mph' | 'ms')
                                    }
                                />
                            </SettingRow>

                            <View style={styles.divider} />

                            <SettingRow icon="time-outline" title="Time">
                                <OptionButtons
                                    options={[
                                        { label: '12h', value: '12h' },
                                        { label: '24h', value: '24h' },
                                    ]}
                                    selected={settings.timeFormat}
                                    onSelect={(value) =>
                                        handleSettingChange('timeFormat', value as '12h' | '24h')
                                    }
                                />
                            </SettingRow>
                        </View>
                    </BlurView>

                    {/* Notifications */}
                    <BlurView intensity={40} tint="dark" style={styles.section}>
                        <View style={styles.sectionOverlay}>
                            <Text style={styles.sectionTitle}>NOTIFICATIONS</Text>

                            <SettingRow icon="notifications-outline" title="Enable">
                                <Switch
                                    value={settings.notificationsEnabled}
                                    onValueChange={(value) =>
                                        handleSettingChange('notificationsEnabled', value)
                                    }
                                    trackColor={{ false: 'rgba(255,255,255,0.1)', true: 'rgba(249, 115, 22, 0.6)' }}
                                    thumbColor="#fff"
                                    ios_backgroundColor="rgba(255,255,255,0.1)"
                                />
                            </SettingRow>
                        </View>
                    </BlurView>

                    {/* About */}
                    <BlurView intensity={40} tint="dark" style={styles.section}>
                        <View style={styles.sectionOverlay}>
                            <Text style={styles.sectionTitle}>ABOUT</Text>

                            <SettingRow icon="information-circle-outline" title="Version">
                                <Text style={styles.valueText}>1.0.0</Text>
                            </SettingRow>
                        </View>
                    </BlurView>
                </ScrollView>
            </SafeAreaView>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#121214',
    },
    safeArea: {
        flex: 1,
    },
    header: {
        paddingHorizontal: 24,
        paddingTop: 12,
        paddingBottom: 20,
    },
    title: {
        fontFamily: 'SpaceMono',
        fontSize: 28,
        fontWeight: '400',
        color: '#fff',
    },
    subtitle: {
        fontFamily: 'SpaceMono',
        fontSize: 12,
        color: 'rgba(255,255,255,0.35)',
        marginTop: 4,
    },
    scrollView: {
        flex: 1,
    },
    scrollContent: {
        paddingHorizontal: 20,
        paddingBottom: 120,
        gap: 12,
    },
    section: {
        borderRadius: 20,
        overflow: 'hidden',
    },
    sectionOverlay: {
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
    settingRow: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        paddingVertical: 8,
    },
    settingLeft: {
        flexDirection: 'row',
        alignItems: 'center',
        flex: 1,
    },
    settingIcon: {
        width: 28,
        height: 28,
        borderRadius: 8,
        backgroundColor: 'rgba(249, 115, 22, 0.15)',
        justifyContent: 'center',
        alignItems: 'center',
        marginRight: 12,
    },
    settingTitle: {
        fontFamily: 'SpaceMono',
        fontSize: 13,
        color: 'rgba(255,255,255,0.7)',
    },
    divider: {
        height: 1,
        backgroundColor: 'rgba(255, 255, 255, 0.06)',
        marginVertical: 8,
    },
    optionButtons: {
        flexDirection: 'row',
        gap: 6,
    },
    optionButton: {
        paddingHorizontal: 12,
        paddingVertical: 6,
        borderRadius: 8,
        backgroundColor: 'rgba(255, 255, 255, 0.08)',
    },
    optionButtonActive: {
        backgroundColor: 'rgba(249, 115, 22, 0.6)',
    },
    optionText: {
        fontFamily: 'SpaceMono',
        fontSize: 12,
        color: 'rgba(255,255,255,0.4)',
    },
    optionTextActive: {
        color: '#fff',
    },
    valueText: {
        fontFamily: 'SpaceMono',
        fontSize: 12,
        color: 'rgba(255,255,255,0.35)',
    },
});
