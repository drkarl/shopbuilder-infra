# =============================================================================
# Stage 1: Build
# =============================================================================
# Build the Node.js frontend application
FROM node:20-alpine AS build

WORKDIR /app

# Install dependencies first (better layer caching)
COPY package*.json ./
RUN npm ci --silent

# Copy source code
COPY . .

# Build-time environment variables (passed via --build-arg)
ARG VITE_API_URL
ARG VITE_SUPABASE_URL
ARG VITE_SUPABASE_ANON_KEY

# Validate required build args
RUN if [ -z "$VITE_API_URL" ]; then \
      echo "ERROR: VITE_API_URL build arg is required" && exit 1; \
    fi

# Build the application with optimizations
ENV NODE_ENV=production
RUN npm run build

# =============================================================================
# Stage 2: Runtime
# =============================================================================
# Serve the static files with Nginx
FROM nginx:1.27-alpine AS runtime

# Install curl for health checks
RUN apk add --no-cache curl

# Remove default nginx configuration
RUN rm /etc/nginx/conf.d/default.conf

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf
COPY security-headers.conf /etc/nginx/security-headers.conf

# Copy built static files from build stage
COPY --from=build /app/dist /usr/share/nginx/html

# Set up permissions for non-root nginx user
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid

# Switch to non-root user
USER nginx

# Expose port 8080 (non-privileged port for non-root user)
EXPOSE 8080

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run nginx in foreground
CMD ["nginx", "-g", "daemon off;"]
