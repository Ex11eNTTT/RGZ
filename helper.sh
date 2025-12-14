#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 1. Настройка базы данных (АДАПТИРОВАНО ДЛЯ WINDOWS)
setup_database() {
    print_info "Setting up PostgreSQL database for Windows..."
    
    # Проверяем, доступен ли psql
    if ! command -v psql &> /dev/null; then
        print_error "PostgreSQL client (psql) is not found in PATH."
        print_info "Add PostgreSQL to PATH:"
        echo "1. Find psql.exe at: C:\\Program Files\\PostgreSQL\\<version>\\bin"
        echo "2. Add this path to System Environment Variables"
        echo "Or use full path like: '/c/Program Files/PostgreSQL/17/bin/psql'"
        return 1
    fi
    
    # Запрашиваем пароль
    echo -n "Enter PostgreSQL password for 'postgres' user: "
    read -s db_password
    echo ""
    
    # Проверяем подключение
    print_info "Testing PostgreSQL connection..."
    if ! PGPASSWORD="$db_password" psql -U postgres -h localhost -c "SELECT 1;" &> /dev/null; then
        print_error "Cannot connect to PostgreSQL. Possible issues:"
        echo "1. Wrong password"
        echo "2. PostgreSQL service not running"
        echo "3. Check with: services.msc (look for 'postgresql')"
        return 1
    fi
    
    # Создаем базу данных
    print_info "Creating database 'subscriptions_db'..."
    
    # Удаляем базу если существует (для чистого теста)
    PGPASSWORD="$db_password" psql -U postgres -h localhost -c "DROP DATABASE IF EXISTS subscriptions_db;" 2>/dev/null
    
    # Создаем новую базу
    if PGPASSWORD="$db_password" psql -U postgres -h localhost -c "CREATE DATABASE subscriptions_db;"; then
        print_info "✓ Database 'subscriptions_db' created successfully!"
    else
        print_error "Failed to create database"
        return 1
    fi
    
    # Обновляем config.py с правильным паролем
    print_info "Updating config.py with your password..."
    if [[ -f "config.py" ]]; then
        # Создаем backup оригинального файла
        cp config.py config.py.backup
        
        # Обновляем строку подключения в config.py
        sed -i "s|postgresql://postgres:.*@localhost:5432/subscriptions_db|postgresql://postgres:$db_password@localhost:5432/subscriptions_db|g" config.py
        
        # Для Windows-стиля пути (дополнительная строка)
        sed -i "s|:password@|:$db_password@|g" config.py
        
        print_info "✓ config.py updated"
    else
        print_warning "config.py not found, creating basic config..."
        cat > config.py << EOF
import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    SQLALCHEMY_DATABASE_URI = 'postgresql://postgres:$db_password@localhost:5432/subscriptions_db'
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SECRET_KEY = 'dev-secret-key-change-in-production'
EOF
    fi
    
    print_info "Database setup completed!"
    echo ""
    print_info "To verify database:"
    echo "  psql -U postgres -l | grep subscriptions_db"
}

# 2. Установка зависимостей (РАБОТАЕТ НА WINDOWS)
install_dependencies() {
    print_info "Installing Python dependencies..."
    
    # Проверяем Python
    if ! command -v python &> /dev/null && ! command -v python3 &> /dev/null; then
        print_error "Python is not installed. Please install Python 3.8+"
        return 1
    fi
    
    # Используем python или python3
    if command -v python &> /dev/null; then
        PYTHON_CMD="python"
    else
        PYTHON_CMD="python3"
    fi
    
    # Создаем виртуальное окружение
    if [[ ! -d "venv" ]]; then
        print_info "Creating virtual environment..."
        $PYTHON_CMD -m venv venv
    fi
    
    # Активируем виртуальное окружение
    print_info "Activating virtual environment..."
    
    # Для Windows/Git Bash
    if [[ -f "venv/Scripts/activate" ]]; then
        source venv/Scripts/activate
    elif [[ -f "venv/bin/activate" ]]; then
        source venv/bin/activate
    else
        print_error "Cannot find virtual environment activation script"
        return 1
    fi
    
    # Обновляем pip и устанавливаем зависимости
    print_info "Installing packages from requirements.txt..."
    pip install --upgrade pip
    
    if [[ -f "requirements.txt" ]]; then
        pip install -r requirements.txt
        print_info "✓ Dependencies installed successfully!"
    else
        print_warning "requirements.txt not found, installing basic packages..."
        pip install Flask==2.3.3 Flask-SQLAlchemy==3.0.5 psycopg2-binary==2.9.7 python-dotenv==1.0.0
    fi
    
    # Деактивируем окружение
    deactivate
    print_info "Virtual environment deactivated"
}

# 3. Запуск приложения (АДАПТИРОВАНО ДЛЯ WINDOWS)
start_app() {
    print_info "Starting Flask application..."
    
    # Проверяем, запущено ли уже приложение
    if [[ -f "flask.pid" ]]; then
        PID=$(cat flask.pid)
        if ps -p $PID &> /dev/null; then
            print_warning "Application is already running (PID: $PID)"
            echo "Use './helper.sh stop' to stop it first"
            return 1
        fi
    fi
    
    # Активируем виртуальное окружение
    if [[ -f "venv/Scripts/activate" ]]; then
        source venv/Scripts/activate
    elif [[ -f "venv/bin/activate" ]]; then
        source venv/bin/activate
    else
        print_error "Virtual environment not found. Run './helper.sh install' first"
        return 1
    fi
    
    # Проверяем config.py
    if [[ ! -f "config.py" ]]; then
        print_error "config.py not found. Run './helper.sh setup_db' first"
        deactivate
        return 1
    fi
    
    # Экспортируем переменные окружения
    export FLASK_APP=app.py
    export FLASK_ENV=development
    
    # Создаем таблицы в базе если их нет
    print_info "Creating database tables (if not exist)..."
    python -c "
from app import app, db
with app.app_context():
    db.create_all()
    print('✓ Tables checked/created')
    " 2>/dev/null || print_warning "Could not create tables (might already exist)"
    
    # Запускаем приложение
    print_info "Starting Flask server on http://localhost:5000"
    echo -e "${BLUE}Press Ctrl+C to stop the server${NC}"
    echo ""
    
    # Запускаем в фоновом режиме и сохраняем PID
    nohup python app.py > app.log 2>&1 &
    FLASK_PID=$!
    echo $FLASK_PID > flask.pid
    
    # Ждем немного и проверяем
    sleep 2
    if ps -p $FLASK_PID &> /dev/null; then
        print_info "✓ Application started successfully! (PID: $FLASK_PID)"
        print_info "Logs are being written to: app.log"
        print_info "View logs: tail -f app.log"
        echo ""
        print_info "Test the API:"
        echo "  curl http://localhost:5000/"
        echo "  or open in browser: http://localhost:5000"
    else
        print_error "Failed to start application"
        print_info "Check error logs: cat app.log"
        rm -f flask.pid
    fi
    
    # Не деактивируем окружение - оно нужно для работы приложения
}

# 4. Остановка приложения (РАБОТАЕТ НА WINDOWS)
stop_app() {
    if [[ -f "flask.pid" ]]; then
        PID=$(cat flask.pid)
        print_info "Stopping Flask application (PID: $PID)..."
        
        if ps -p $PID &> /dev/null; then
            kill $PID 2>/dev/null
            sleep 1
            
            if ps -p $PID &> /dev/null; then
                print_warning "Graceful stop failed, forcing..."
                kill -9 $PID 2>/dev/null
            fi
            
            print_info "✓ Application stopped"
        else
            print_warning "No running process found with PID: $PID"
        fi
        
        rm -f flask.pid
    else
        print_warning "No PID file found. Stopping all Python Flask processes..."
        # Ищем и останавливаем все процессы Flask
        pkill -f "python.*app.py" 2>/dev/null || print_info "No Flask processes found"
    fi
    
    # Убеждаемся что порт 5000 свободен
    if netstat -an | grep ":5000.*LISTEN" &> /dev/null; then
        print_warning "Port 5000 is still in use. You may need to restart terminal."
    fi
}

# 5. Запуск тестов (АДАПТИРОВАНО ДЛЯ WINDOWS)
run_tests() {
    print_info "Running tests..."
    
    # Активируем виртуальное окружение
    if [[ -f "venv/Scripts/activate" ]]; then
        source venv/Scripts/activate
    elif [[ -f "venv/bin/activate" ]]; then
        source venv/bin/activate
    else
        print_error "Virtual environment not found"
        return 1
    fi
    
    # Проверяем наличие pytest
    if ! pip list | grep -q pytest; then
        print_info "Installing pytest..."
        pip install pytest
    fi
    
    # Создаем тестовую базу данных
    print_info "Setting up test database..."
    read -p "Enter PostgreSQL password for tests: " -s test_password
    echo ""
    
    PGPASSWORD="$test_password" psql -U postgres -h localhost -c "DROP DATABASE IF EXISTS test_subscriptions_db;" 2>/dev/null
    PGPASSWORD="$test_password" psql -U postgres -h localhost -c "CREATE DATABASE test_subscriptions_db;" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        print_info "✓ Test database created"
        
        # Запускаем тесты
        export TESTING=True
        export DATABASE_URL="postgresql://postgres:$test_password@localhost:5432/test_subscriptions_db"
        
        if [[ -d "tests" ]]; then
            python -m pytest tests/ -v
        else
            print_warning "No tests directory found"
            echo "Creating basic test structure..."
            mkdir -p tests
            cat > tests/test_basic.py << 'EOF'
import pytest

def test_basic():
    assert 1 + 1 == 2

if __name__ == '__main__':
    pytest.main()
EOF
            python -m pytest tests/ -v
        fi
        
        # Очищаем тестовую базу
        PGPASSWORD="$test_password" psql -U postgres -h localhost -c "DROP DATABASE test_subscriptions_db;" 2>/dev/null
    else
        print_error "Failed to create test database"
    fi
    
    deactivate
}

# 6. Дополнительные команды
show_logs() {
    if [[ -f "app.log" ]]; then
        print_info "Showing last 50 lines of app.log:"
        echo "----------------------------------------"
        tail -50 app.log
        echo "----------------------------------------"
        print_info "Follow logs in real-time: tail -f app.log"
    else
        print_warning "No log file found"
    fi
}

check_status() {
    print_info "Checking application status..."
    
    # Проверяем базу данных
    if command -v psql &> /dev/null; then
        echo -n "Database 'subscriptions_db': "
        if psql -U postgres -h localhost -l 2>/dev/null | grep -q subscriptions_db; then
            echo -e "${GREEN}EXISTS${NC}"
        else
            echo -e "${RED}NOT FOUND${NC}"
        fi
    fi
    
    # Проверяем запущено ли приложение
    if [[ -f "flask.pid" ]]; then
        PID=$(cat flask.pid)
        if ps -p $PID &> /dev/null; then
            echo -e "Flask app: ${GREEN}RUNNING${NC} (PID: $PID, Port: 5000)"
            echo "URL: http://localhost:5000"
        else
            echo -e "Flask app: ${RED}STOPPED${NC} (stale PID file)"
            rm -f flask.pid
        fi
    else
        echo -e "Flask app: ${YELLOW}NOT RUNNING${NC}"
    fi
    
    # Проверяем виртуальное окружение
    if [[ -d "venv" ]]; then
        echo -e "Virtual env: ${GREEN}EXISTS${NC}"
    else
        echo -e "Virtual env: ${RED}NOT FOUND${NC}"
    fi
}

reset_all() {
    print_warning "This will reset everything: stop app, delete database and venv"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ./helper.sh stop
        
        print_info "Dropping database..."
        read -p "Enter PostgreSQL password: " -s db_password
        echo ""
        PGPASSWORD="$db_password" psql -U postgres -h localhost -c "DROP DATABASE subscriptions_db;" 2>/dev/null
        
        print_info "Removing virtual environment..."
        rm -rf venv
        
        print_info "Cleaning up files..."
        rm -f app.log flask.pid config.py.backup
        
        print_info "✓ Full reset completed"
    else
        print_info "Reset cancelled"
    fi
}

# Основное меню помощи
show_help() {
    echo -e "${BLUE}Financial Subscriptions Helper - Windows Version${NC}"
    echo "=========================================="
    echo "Available commands:"
    echo ""
    echo -e "${GREEN}Database:${NC}"
    echo "  ./helper.sh setup_db    - Setup PostgreSQL database"
    echo ""
    echo -e "${GREEN}Application:${NC}"
    echo "  ./helper.sh install     - Install dependencies"
    echo "  ./helper.sh start       - Start Flask application"
    echo "  ./helper.sh stop        - Stop Flask application"
    echo "  ./helper.sh restart     - Restart application"
    echo ""
    echo -e "${GREEN}Testing:${NC}"
    echo "  ./helper.sh test        - Run tests"
    echo ""
    echo -e "${GREEN}Utilities:${NC}"
    echo "  ./helper.sh logs        - Show application logs"
    echo "  ./helper.sh status      - Check system status"
    echo "  ./helper.sh reset       - Reset everything (careful!)"
    echo "  ./helper.sh help        - Show this help"
    echo ""
    echo -e "${YELLOW}Note for Windows/Git Bash users:${NC}"
    echo "1. PostgreSQL must be installed and in PATH"
    echo "2. Use './helper.sh setup_db' first to configure database"
    echo "3. Default URL: http://localhost:5000"
}

# Обработка команд
case "$1" in
    setup_db)
        setup_database
        ;;
    install)
        install_dependencies
        ;;
    start)
        start_app
        ;;
    stop)
        stop_app
        ;;
    restart)
        stop_app
        sleep 2
        start_app
        ;;
    test)
        run_tests
        ;;
    logs)
        show_logs
        ;;
    status)
        check_status
        ;;
    reset)
        reset_all
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Usage: $0 {setup_db|install|start|stop|restart|test|logs|status|reset|help}"
        echo "Run '$0 help' for detailed information"
        exit 1
        ;;
esac