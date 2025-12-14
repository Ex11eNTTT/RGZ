import pytest
from app import app
from database import db
import json

@pytest.fixture
def client():
    app.config['TESTING'] = True
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///:memory:'
    
    with app.test_client() as client:
        with app.app_context():
            db.create_all()
        yield client

def test_create_subscription(client):
    data = {
        'name': 'Netflix',
        'amount': 12.99,
        'period': 'monthly',
        'start_date': '2024-01-01'
    }
    
    response = client.post('/api/subscriptions', 
                         json=data,
                         content_type='application/json')
    
    assert response.status_code == 201
    json_data = json.loads(response.data)
    assert json_data['name'] == 'Netflix'
    assert json_data['amount'] == 12.99

def test_get_subscriptions(client):
    # Сначала создаем подписку
    data = {
        'name': 'Spotify',
        'amount': 9.99,
        'period': 'monthly',
        'start_date': '2024-01-01'
    }
    client.post('/api/subscriptions', json=data)
    
    # Получаем все подписки
    response = client.get('/api/subscriptions')
    
    assert response.status_code == 200
    json_data = json.loads(response.data)
    assert len(json_data) > 0

def test_update_subscription(client):
    # Создаем подписку
    data = {
        'name': 'Youtube Premium',
        'amount': 15.99,
        'period': 'monthly',
        'start_date': '2024-01-01'
    }
    create_resp = client.post('/api/subscriptions', json=data)
    sub_id = json.loads(create_resp.data)['id']
    
    # Обновляем подписку
    update_data = {'amount': 17.99}
    response = client.put(f'/api/subscriptions/{sub_id}', json=update_data)
    
    assert response.status_code == 200
    json_data = json.loads(response.data)
    assert json_data['amount'] == 17.99

def test_delete_subscription(client):
    # Создаем подписку
    data = {
        'name': 'Delete Test',
        'amount': 5.99,
        'period': 'monthly',
        'start_date': '2024-01-01'
    }
    create_resp = client.post('/api/subscriptions', json=data)
    sub_id = json.loads(create_resp.data)['id']
    
    # Удаляем подписку
    response = client.delete(f'/api/subscriptions/{sub_id}')
    
    assert response.status_code == 200
    json_data = json.loads(response.data)
    assert 'deleted successfully' in json_data['message']