import { Alarm, deleteAlarm, getAlarms, saveAlarms, updateAlarm } from '@/services/storage';
import { formatTimeInTimezone } from '@/utils/coordinates';
import { Ionicons } from '@expo/vector-icons';
import { BlurView } from 'expo-blur';
import { useEffect, useState } from 'react';
import {
    Alert,
    ScrollView,
    StyleSheet,
    Switch,
    Text,
    TouchableOpacity,
    View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

const TIMEZONES = [
    { label: 'New York', value: 'America/New_York' },
    { label: 'Los Angeles', value: 'America/Los_Angeles' },
    { label: 'London', value: 'Europe/London' },
    { label: 'Paris', value: 'Europe/Paris' },
    { label: 'Tokyo', value: 'Asia/Tokyo' },
    { label: 'Sydney', value: 'Australia/Sydney' },
];

export default function AlarmsScreen() {
    const [alarms, setAlarms] = useState<Alarm[]>([]);

    useEffect(() => {
        loadAlarms();
    }, []);

    const loadAlarms = async () => {
        const loaded = await getAlarms();
        setAlarms(loaded);
    };

    const handleToggleAlarm = async (alarm: Alarm) => {
        const updated = { ...alarm, enabled: !alarm.enabled };
        await updateAlarm(updated);
        loadAlarms();
    };

    const handleDeleteAlarm = async (alarmId: string) => {
        Alert.alert('Delete Alarm', 'Are you sure?', [
            { text: 'Cancel', style: 'cancel' },
            {
                text: 'Delete',
                style: 'destructive',
                onPress: async () => {
                    await deleteAlarm(alarmId);
                    loadAlarms();
                },
            },
        ]);
    };

    const handleAddAlarm = async () => {
        const newAlarm: Alarm = {
            id: Date.now().toString(),
            time: '08:00',
            timezone: 'America/New_York',
            label: 'Wake up',
            enabled: true,
            days: [1, 2, 3, 4, 5],
        };
        await saveAlarms([...alarms, newAlarm]);
        loadAlarms();
    };

    const renderAlarmCard = (alarm: Alarm) => {
        const currentTimeInZone = formatTimeInTimezone(alarm.timezone, '12h');
        const tzLabel = TIMEZONES.find(tz => tz.value === alarm.timezone)?.label || alarm.timezone;

        return (
            <TouchableOpacity
                key={alarm.id}
                activeOpacity={0.8}
                onLongPress={() => handleDeleteAlarm(alarm.id)}
            >
                <BlurView intensity={40} tint="dark" style={styles.alarmCard}>
                    <View style={styles.cardOverlay}>
                        <View style={styles.alarmHeader}>
                            <View>
                                <Text style={styles.alarmTime}>{alarm.time}</Text>
                                <Text style={styles.alarmLabel}>{alarm.label}</Text>
                            </View>
                            <Switch
                                value={alarm.enabled}
                                onValueChange={() => handleToggleAlarm(alarm)}
                                trackColor={{ false: 'rgba(255,255,255,0.1)', true: 'rgba(249, 115, 22, 0.6)' }}
                                thumbColor="#fff"
                                ios_backgroundColor="rgba(255,255,255,0.1)"
                            />
                        </View>

                        <View style={styles.timezoneRow}>
                            <Ionicons name="globe-outline" size={12} color="rgba(255,255,255,0.4)" />
                            <Text style={styles.timezoneText}>{tzLabel}</Text>
                            <Text style={styles.localTime}>· {currentTimeInZone}</Text>
                        </View>

                        <View style={styles.daysRow}>
                            {['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((day, index) => (
                                <View
                                    key={index}
                                    style={[
                                        styles.dayBadge,
                                        alarm.days.includes(index) && styles.dayBadgeActive,
                                    ]}
                                >
                                    <Text
                                        style={[
                                            styles.dayText,
                                            alarm.days.includes(index) && styles.dayTextActive,
                                        ]}
                                    >
                                        {day}
                                    </Text>
                                </View>
                            ))}
                        </View>
                    </View>
                </BlurView>
            </TouchableOpacity>
        );
    };

    return (
        <View style={styles.container}>
            <SafeAreaView style={styles.safeArea}>
                <View style={styles.header}>
                    <Text style={styles.title}>Alarms</Text>
                    <Text style={styles.subtitle}>Multi-timezone</Text>
                </View>

                <ScrollView
                    style={styles.scrollView}
                    contentContainerStyle={styles.scrollContent}
                    showsVerticalScrollIndicator={false}
                >
                    {alarms.length === 0 ? (
                        <View style={styles.emptyState}>
                            <Ionicons name="alarm-outline" size={40} color="rgba(255,255,255,0.15)" />
                            <Text style={styles.emptyText}>No alarms</Text>
                        </View>
                    ) : (
                        alarms.map(renderAlarmCard)
                    )}
                </ScrollView>

                {/* Add Button */}
                <View style={styles.addButtonContainer}>
                    <TouchableOpacity style={styles.addButton} onPress={handleAddAlarm} activeOpacity={0.8}>
                        <Ionicons name="add" size={24} color="#fff" />
                    </TouchableOpacity>
                </View>
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
        paddingBottom: 140,
    },
    alarmCard: {
        borderRadius: 20,
        overflow: 'hidden',
        marginBottom: 12,
    },
    cardOverlay: {
        backgroundColor: 'rgba(18, 18, 20, 0.7)',
        padding: 20,
    },
    alarmHeader: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'flex-start',
        marginBottom: 12,
    },
    alarmTime: {
        fontFamily: 'SpaceMono',
        fontSize: 36,
        fontWeight: '400',
        color: '#fff',
    },
    alarmLabel: {
        fontFamily: 'SpaceMono',
        fontSize: 13,
        color: 'rgba(255,255,255,0.5)',
        marginTop: 4,
    },
    timezoneRow: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 6,
        marginBottom: 14,
    },
    timezoneText: {
        fontFamily: 'SpaceMono',
        fontSize: 11,
        color: 'rgba(255, 255, 255, 0.4)',
    },
    localTime: {
        fontFamily: 'SpaceMono',
        fontSize: 11,
        color: 'rgba(255, 255, 255, 0.3)',
    },
    daysRow: {
        flexDirection: 'row',
        gap: 6,
    },
    dayBadge: {
        width: 28,
        height: 28,
        borderRadius: 14,
        backgroundColor: 'rgba(255, 255, 255, 0.08)',
        justifyContent: 'center',
        alignItems: 'center',
    },
    dayBadgeActive: {
        backgroundColor: 'rgba(249, 115, 22, 0.7)',
    },
    dayText: {
        fontFamily: 'SpaceMono',
        fontSize: 10,
        color: 'rgba(255, 255, 255, 0.35)',
    },
    dayTextActive: {
        color: '#fff',
    },
    emptyState: {
        alignItems: 'center',
        justifyContent: 'center',
        paddingTop: 100,
    },
    emptyText: {
        fontFamily: 'SpaceMono',
        fontSize: 14,
        color: 'rgba(255,255,255,0.35)',
        marginTop: 12,
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
