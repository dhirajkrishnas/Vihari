import { Ionicons } from '@expo/vector-icons';
import { Tabs } from 'expo-router';
import React from 'react';

function TabBarIcon(props: {
  name: React.ComponentProps<typeof Ionicons>['name'];
  color: string;
}) {
  return <Ionicons size={22} style={{ marginBottom: -2 }} {...props} />;
}

export default function TabLayout() {
  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: '#f97316',
        tabBarInactiveTintColor: 'rgba(255, 255, 255, 0.35)',
        tabBarStyle: {
          position: 'absolute',
          backgroundColor: '#121214',
          borderTopColor: 'rgba(255, 255, 255, 0.06)',
          borderTopWidth: 1,
          height: 85,
          paddingBottom: 30,
          paddingTop: 10,
        },
        tabBarLabelStyle: {
          fontFamily: 'SpaceMono',
          fontSize: 10,
        },
        headerShown: false,
      }}>
      <Tabs.Screen
        name="index"
        options={{
          title: 'Home',
          tabBarIcon: ({ color, focused }) => (
            <TabBarIcon name={focused ? 'globe' : 'globe-outline'} color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="alarms"
        options={{
          title: 'Alarms',
          tabBarIcon: ({ color, focused }) => (
            <TabBarIcon name={focused ? 'alarm' : 'alarm-outline'} color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="settings"
        options={{
          title: 'Settings',
          tabBarIcon: ({ color, focused }) => (
            <TabBarIcon name={focused ? 'settings' : 'settings-outline'} color={color} />
          ),
        }}
      />
    </Tabs>
  );
}
