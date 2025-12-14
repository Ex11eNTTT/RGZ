from flask import Flask, request, jsonify
from config import Config
from database import db
from models import User, Subscription, AuditLog
from datetime import datetime
import os

app = Flask(__name__)
app.config.from_object(Config)
db.init_app(app)

# Создаем таблицы и тестового пользователя сразу
with app.app_context():
    db.create_all()
    if not User.query.filter_by(username='test_user').first():
        user = User(username='test_user')
        db.session.add(user)
        db.session.commit()

# 1. Создание подписки
@app.route('/api/subscriptions', methods=['POST'])
def create_subscription():
    data = request.json
    user_id = 1  # Для демо используем первого пользователя
    
    try:
        subscription = Subscription(
            user_id=user_id,
            name=data['name'],
            amount=float(data['amount']),
            period=data['period'],
            start_date=datetime.strptime(data['start_date'], '%Y-%m-%d').date()
        )
        
        db.session.add(subscription)
        
        # Логируем действие
        audit = AuditLog(
            user_id=user_id,
            action='CREATE_SUBSCRIPTION',
            subscription_id=subscription.id,
            details=f"Created subscription: {data['name']}"
        )
        db.session.add(audit)
        
        db.session.commit()
        
        return jsonify({
            'id': subscription.id,
            'name': subscription.name,
            'amount': subscription.amount,
            'period': subscription.period,
            'start_date': subscription.start_date.isoformat()
        }), 201
        
    except Exception as e:
        return jsonify({'error': str(e)}), 400

# 2. Просмотр подписок
@app.route('/api/subscriptions', methods=['GET'])
def get_subscriptions():
    user_id = 1  # Для демо
    subscriptions = Subscription.query.filter_by(user_id=user_id, is_active=True).all()
    
    result = []
    for sub in subscriptions:
        result.append({
            'id': sub.id,
            'name': sub.name,
            'amount': sub.amount,
            'period': sub.period,
            'start_date': sub.start_date.isoformat(),
            'created_at': sub.created_at.isoformat()
        })
    
    return jsonify(result), 200

# 3. Редактирование подписки
@app.route('/api/subscriptions/<int:subscription_id>', methods=['PUT'])
def update_subscription(subscription_id):
    data = request.json
    user_id = 1
    
    subscription = Subscription.query.filter_by(id=subscription_id, user_id=user_id).first()
    if not subscription:
        return jsonify({'error': 'Subscription not found'}), 404
    
    try:
        if 'name' in data:
            subscription.name = data['name']
        if 'amount' in data:
            subscription.amount = float(data['amount'])
        if 'period' in data:
            subscription.period = data['period']
        if 'start_date' in data:
            subscription.start_date = datetime.strptime(data['start_date'], '%Y-%m-%d').date()
        
        # Логируем действие
        audit = AuditLog(
            user_id=user_id,
            action='UPDATE_SUBSCRIPTION',
            subscription_id=subscription.id,
            details=f"Updated subscription: {subscription.name}"
        )
        db.session.add(audit)
        
        db.session.commit()
        
        return jsonify({
            'id': subscription.id,
            'name': subscription.name,
            'amount': subscription.amount,
            'period': subscription.period,
            'start_date': subscription.start_date.isoformat()
        }), 200
        
    except Exception as e:
        return jsonify({'error': str(e)}), 400

# 4. Удаление подписки
@app.route('/api/subscriptions/<int:subscription_id>', methods=['DELETE'])
def delete_subscription(subscription_id):
    user_id = 1
    
    subscription = Subscription.query.filter_by(id=subscription_id, user_id=user_id).first()
    if not subscription:
        return jsonify({'error': 'Subscription not found'}), 404
    
    # Мягкое удаление (деактивация)
    subscription.is_active = False
    
    # Логируем действие
    audit = AuditLog(
        user_id=user_id,
        action='DELETE_SUBSCRIPTION',
        subscription_id=subscription.id,
        details=f"Deleted subscription: {subscription.name}"
    )
    db.session.add(audit)
    
    db.session.commit()
    
    return jsonify({'message': 'Subscription deleted successfully'}), 200

@app.route('/')
def index():
    return jsonify({
        'message': 'Financial Subscriptions API',
        'endpoints': {
            'GET /api/subscriptions': 'Get all subscriptions',
            'POST /api/subscriptions': 'Create subscription',
            'PUT /api/subscriptions/<id>': 'Update subscription',
            'DELETE /api/subscriptions/<id>': 'Delete subscription'
        }
    })

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
    app.run(debug=True, port=5000)