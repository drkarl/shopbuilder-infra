# =============================================================================
# ShopBuilder Spring Boot Backend Dockerfile
# Multi-stage build for optimized runtime image
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Build stage - Compile and package the application
# -----------------------------------------------------------------------------
FROM gradle:8-jdk21 AS build

WORKDIR /app

# Copy Gradle configuration files first for dependency caching
COPY build.gradle.kts settings.gradle.kts gradle.properties* ./
COPY gradle ./gradle

# Download dependencies (cached layer unless build files change)
RUN gradle dependencies --no-daemon || true

# Copy source code
COPY src ./src

# Build the application
ARG BUILD_PROFILE=production
RUN gradle bootJar --no-daemon -Dspring.profiles.active=${BUILD_PROFILE}

# -----------------------------------------------------------------------------
# Stage 2: Runtime stage - Minimal JRE with the application
# -----------------------------------------------------------------------------
FROM eclipse-temurin:21-jre AS runtime

# Create non-root user for security
RUN groupadd --gid 1000 spring && \
    useradd --uid 1000 --gid spring --shell /bin/bash --create-home spring

WORKDIR /app

# Install curl for health checks
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Copy the built JAR from build stage with correct ownership
COPY --from=build --chown=spring:spring /app/build/libs/*.jar app.jar

# Switch to non-root user
USER spring

# Expose the application port
EXPOSE 8080

# JVM arguments for production with virtual threads support
# ZGC provides low-latency garbage collection suitable for virtual threads
# Virtual threads are enabled by default in JDK 21+
ENV JAVA_TOOL_OPTIONS="-XX:+UseZGC -XX:+ZGenerational -Xmx2g -Xms512m -XX:+ExitOnOutOfMemoryError -Djava.security.egd=file:/dev/./urandom"

# Health check configuration
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s \
    CMD curl -f http://localhost:8080/actuator/health || exit 1

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]
