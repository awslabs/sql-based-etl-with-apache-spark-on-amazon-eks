#!/bin/bash

export stack_name="${1:-SparkOnEKS}"
lower_stack_name=$(echo $stack_name | tr '[:upper:]' '[:lower:]')

# delete s3
code_bucket=$(aws cloudformation describe-stacks --stack-name $stack_name --query "Stacks[0].Outputs[?OutputKey=='CODEBUCKET'].OutputValue" --output text)
if ! [ -z "$code_bucket" ] 
then	
	if ! [ -z $(aws s3api list-buckets --query 'Buckets[?Name==`'$code_bucket'`].Name' --output text) ]; then
		echo "Delete logs from S3"
		aws s3 rm s3://${code_bucket}/vpcRejectlog/
		echo "Delete athena query result from S3"
		aws s3 rm s3://${code_bucket}/athena-query-result/
	fi	
fi
# delete ecr
repo_name=$(aws ecr describe-repositories --query 'repositories[?starts_with(repositoryName,`'$lower_stack_name'`)==`true`]'.repositoryName --output text)
if ! [ -z "$repo_name" ]; then
	repo_exist=$(aws ecr describe-repositories --repository-names ${repo_name} 2>&1)
	if ! [ -z "$repo_exist" ]; then	
    	echo "Delete Arc docker image from ECR"
		aws ecr delete-repository --repository-name $repo_name --force
  	fi
fi
# delete glue tables
tbl1=$(aws glue get-tables --database-name 'default' --query 'TableList[?starts_with(Name,`contact_snapshot`)==`true`]'.Name --output text)
tbl2=$(aws glue get-tables --database-name 'default' --query 'TableList[?starts_with(Name,`deltalake_contact_jhub`)==`true`]'.Name --output text)
if ! [ -z "$tbl1" ] 
then
	echo "Drop a Delta Lake table default.contact_snapshot"
	aws athena start-query-execution --query-string "DROP TABLE default.contact_snapshot" --result-configuration OutputLocation=s3://$code_bucket/athena-query-result
fi
if ! [ -z "$tbl2" ] 
then
	echo "Drop a Delta Lake table default.deltalake_contact_jhub"
	aws athena start-query-execution --query-string "DROP TABLE default.deltalake_contact_jhub" --result-configuration OutputLocation=s3://$code_bucket/athena-query-result
fi

# delete ALB
argoALB=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?starts_with(DNSName,`k8s-argo`)==`true`].LoadBalancerArn' --output text)
jhubALB=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?starts_with(DNSName,`k8s-jupyter`)==`true`].LoadBalancerArn' --output text)
if ! [ -z "$argoALB" ]
then
	echo "Delete Argo ALB"
	aws elbv2 delete-load-balancer --load-balancer-arn $argoALB
	sleep 5
fi	
if ! [ -z "$jhubALB" ]
then
	echo "Delete Jupyter ALB"
	aws elbv2 delete-load-balancer --load-balancer-arn $jhubALB
	sleep 5
fi

argoTG=$(aws elbv2 describe-target-groups --query 'TargetGroups[?starts_with(TargetGroupName,`k8s-argo`)==`true`].TargetGroupArn' --output text)
jhubTG=$(aws elbv2 describe-target-groups --query 'TargetGroups[?starts_with(TargetGroupName,`k8s-jupyter`)==`true`].TargetGroupArn' --output text)
if ! [ -z "$argoTG" ]
then
	sleep 5
	echo "Delete Argo Target groups"
	aws elbv2 delete-target-group --target-group-arn $argoTG 
fi	
if ! [ -z "$jhubTG" ]
then
	sleep 5
	echo "Delete Jupyter Target groups"
	aws elbv2 delete-target-group --target-group-arn $jhubTG 
fi	

# delete the rest from CF
echo "Delete the rest of resources by CloudFormation delete command"
aws cloudformation delete-stack --stack-name $stack_name