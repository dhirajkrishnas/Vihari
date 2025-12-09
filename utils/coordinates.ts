/**
 * Convert latitude/longitude to 3D sphere coordinates
 * @param lat - Latitude in degrees
 * @param lon - Longitude in degrees
 * @param radius - Sphere radius (default 1)
 */
export function latLonToVector3(
    lat: number,
    lon: number,
    radius: number = 1
): { x: number; y: number; z: number } {
    const phi = (90 - lat) * (Math.PI / 180);
    const theta = (lon + 180) * (Math.PI / 180);

    const x = -(radius * Math.sin(phi) * Math.cos(theta));
    const y = radius * Math.cos(phi);
    const z = radius * Math.sin(phi) * Math.sin(theta);

    return { x, y, z };
}

/**
 * Calculate rotation angles to focus on a specific lat/lon
 * @param lat - Target latitude
 * @param lon - Target longitude
 */
export function getRotationForCoordinates(
    lat: number,
    lon: number
): { rotationX: number; rotationY: number } {
    // Convert to radians
    const latRad = lat * (Math.PI / 180);
    const lonRad = -lon * (Math.PI / 180);

    return {
        rotationX: -latRad,
        rotationY: lonRad - Math.PI / 2,
    };
}

/**
 * Interpolate between two angles smoothly
 */
export function lerpAngle(start: number, end: number, t: number): number {
    // Handle wrapping around 2*PI
    let diff = end - start;
    while (diff > Math.PI) diff -= 2 * Math.PI;
    while (diff < -Math.PI) diff += 2 * Math.PI;
    return start + diff * t;
}

/**
 * Get wind direction as compass text
 */
export function getWindDirection(degrees: number): string {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    const index = Math.round(degrees / 45) % 8;
    return directions[index];
}

/**
 * Format time for a specific timezone
 */
export function formatTimeInTimezone(
    timezone: string,
    format: '12h' | '24h' = '12h'
): string {
    const now = new Date();
    const options: Intl.DateTimeFormatOptions = {
        timeZone: timezone,
        hour: 'numeric',
        minute: '2-digit',
        hour12: format === '12h',
    };
    return new Intl.DateTimeFormat('en-US', options).format(now);
}

/**
 * Convert temperature between units
 */
export function convertTemperature(
    value: number,
    from: 'celsius' | 'fahrenheit',
    to: 'celsius' | 'fahrenheit'
): number {
    if (from === to) return value;
    if (from === 'celsius') {
        return (value * 9) / 5 + 32;
    }
    return ((value - 32) * 5) / 9;
}

/**
 * Convert wind speed between units
 */
export function convertWindSpeed(
    value: number,
    from: 'kmh' | 'mph' | 'ms',
    to: 'kmh' | 'mph' | 'ms'
): number {
    if (from === to) return value;

    // Convert to m/s first
    let ms = value;
    if (from === 'kmh') ms = value / 3.6;
    if (from === 'mph') ms = value * 0.44704;

    // Convert from m/s to target
    if (to === 'ms') return ms;
    if (to === 'kmh') return ms * 3.6;
    return ms / 0.44704;
}
