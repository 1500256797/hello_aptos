compile:
	# 0、compile move contract
	@aptos move compile

test:
	# test move contract
	@aptos move test

deploy:
	# deploy move contract 
	@docker-compose build axum_app && docker-compose up -d    

update:
	# update git dependencies from git repository
	@cargo update